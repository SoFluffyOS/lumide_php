/// PHP runtime and toolchain environment detection service.
library;

import 'dart:io' as io;

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/services/log_service.dart';
import 'package:lumide_php/src/utils/utils.dart';
import 'package:path/path.dart' as p;

class PhpService {
  PhpService(this._context, this._logger);

  final LumideContext _context;
  final LogService _logger;

  String _phpExecutable = 'php';
  String? _phpVersion;
  bool _hasPhp = false;

  String get phpExecutable => _phpExecutable;
  String? get phpVersion => _phpVersion;
  bool get hasPhp => _hasPhp;

  /// Initializes PHP runtime detection.
  Future<bool> init() async {
    final customPath = await _context.workspace.getConfiguration(
      configPhpExecutable,
    );
    if (customPath case final String path when path.trim().isNotEmpty) {
      _phpExecutable = path.trim();
    }

    return checkPhp();
  }

  /// Checks if PHP is available and extracts version info.
  Future<bool> checkPhp() async {
    try {
      final res = await _context.shell.run(_phpExecutable, ['-v']);
      if (res.exitCode != 0) {
        _hasPhp = false;
        _logger.warning('PHP executable returned non-zero code: ${res.stderr}');
        return false;
      }

      _hasPhp = true;
      _phpVersion = _parseVersion(res.stdout);
      _logger.info('Detected PHP version: $_phpVersion');
      return true;
    } catch (e) {
      _hasPhp = false;
      _logger.warning('Failed to execute PHP: $e');
      return false;
    }
  }

  /// Finds a vendor tool (e.g. `vendor/bin/phpunit`) in the workspace, or falls back to global command.
  Future<String> resolveToolExecutable(
    String toolName, {
    String? workspaceRoot,
  }) async {
    final rawRoot = switch (workspaceRoot) {
      final r? => r,
      _ => await _context.workspace.getRootUri() ?? '',
    };
    final root = rawRoot.isNotEmpty ? normalizeFilePath(rawRoot) : '';

    if (root.isNotEmpty) {
      final candidates = switch (io.Platform.isWindows) {
        true => [
            p.join(root, 'vendor', 'bin', '$toolName.bat'),
            p.join(root, 'vendor', 'bin', '$toolName.cmd'),
            p.join(root, 'vendor', 'bin', '$toolName.exe'),
            p.join(root, 'vendor', 'bin', toolName),
          ],
        false => [
            p.join(root, 'vendor', 'bin', toolName),
          ],
      };

      for (final localVendorPath in candidates) {
        final exists = await _context.fs.exists(localVendorPath);
        if (exists) {
          return localVendorPath;
        }
      }
    }

    return toolName;
  }

  /// Parses `PHP 8.2.10 (cli) ...` into a clean version string like `PHP 8.2.10`.
  static String _parseVersion(String rawOutput) {
    final firstLine = rawOutput.split('\n').firstOrNull ?? '';
    final match = RegExp(r'PHP\s+([0-9]+\.[0-9]+(\.[0-9]+)?)').firstMatch(
      firstLine,
    );
    if (match case final m?) {
      final version = m.group(1);
      if (version case final v?) {
        return 'PHP $v';
      }
    }
    return firstLine.trim();
  }

  /// Creates a new PHP file in the selected directory from the context menu.
  Future<void> newPhpFile([Object? args]) async {
    try {
      final targetDirectory = _folderFromContext(args) ??
          await _context.workspace.getRootUri() ??
          '';
      if (targetDirectory.isEmpty) {
        await _context.window.showMessage(
          'No workspace or directory open.',
          title: pluginName,
          type: MessageType.warning,
        );
        return;
      }

      final fileName = await _context.window.showInputBox(
        prompt: 'New PHP File Path / Class Name',
        placeHolder: 'User.php or Controllers/HomeController.php',
      );
      if (fileName == null || fileName.trim().isEmpty) {
        return;
      }

      var cleanName = fileName.trim();
      if (!cleanName.endsWith('.php') && !cleanName.endsWith('.phtml')) {
        cleanName = '$cleanName.php';
      }

      final fullPath = p.isAbsolute(cleanName)
          ? cleanName
          : p.join(targetDirectory, cleanName);

      final exists = await _context.fs.exists(fullPath);
      if (exists) {
        await _context.window.showMessage(
          'File already exists: $cleanName',
          title: pluginName,
          type: MessageType.error,
        );
        return;
      }

      // Create parent directories if nested
      final parentDir = p.dirname(fullPath);
      if (!await _context.fs.exists(parentDir)) {
        await _context.fs.createDirectory(parentDir, recursive: true);
      }

      const template = '<?php\n\ndeclare(strict_types=1);\n\n';
      await _context.fs.writeString(fullPath, template);
      await _context.editor.openDocument(fullPath);
    } catch (e) {
      _logger.error('Failed to create new PHP file', e);
      await _context.window.showMessage(
        'Failed to create PHP file: $e',
        title: pluginName,
        type: MessageType.error,
      );
    }
  }

  String? _folderFromContext(Object? args) {
    if (args == null) {
      return null;
    }
    if (args case final String s when s.isNotEmpty) {
      final norm = normalizeFilePath(s);
      if (norm.endsWith('.php') ||
          norm.endsWith('.json') ||
          p.extension(norm).isNotEmpty) {
        return p.dirname(norm);
      }
      return norm;
    }
    if (args
        case {
          'context': {
            'primary': {
              'path': final String primaryPath,
              'type': final String type
            }
          }
        } when primaryPath.isNotEmpty) {
      final norm = normalizeFilePath(primaryPath);
      if (type == 'directory') {
        return norm;
      }
      if (type == 'file') {
        return p.dirname(norm);
      }
    }
    if (args case {'path': final String pathStr} when pathStr.isNotEmpty) {
      return p.dirname(normalizeFilePath(pathStr));
    }
    return null;
  }
}

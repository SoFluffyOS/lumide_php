import 'dart:io' as io;

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/models/models.dart';
import 'package:lumide_php/src/services/services.dart';
import 'package:lumide_php/src/utils/utils.dart';
import 'package:path/path.dart' as p;

class PhpLspResolver {
  PhpLspResolver(this._context, [this._phpService]);

  final LumideContext _context;
  final PhpService? _phpService;

  Future<PhpLspServer?> resolve(LspServerType type) async {
    if (type == LspServerType.auto) return null;
    if (type == LspServerType.phpactor) {
      final execution = await _resolvePhpactorExecution();
      if (execution == null) return null;
      return PhpLspServer(
          type: type, command: execution.command, args: execution.args);
    }
    if (type == LspServerType.custom) {
      final path = await _context.workspace.getConfiguration(configLspPath);
      if (path is! String || path.trim().isEmpty) return null;
      final command = await findExecutable(_expandUserPath(path.trim()));
      if (command == null) return null;
      return PhpLspServer(
          type: type, command: command, args: const ['--stdio']);
    }
    var command = await findExecutable(type.defaultCommand);
    if (command == null && type == LspServerType.phpLanguageServer) {
      command = await findExecutable('php-language-server.php');
    }
    if (command == null) return null;
    return PhpLspServer(type: type, command: command, args: type.defaultArgs);
  }

  /// Locate commands without starting servers that may wait for protocol input.
  Future<String?> findExecutable(String command) async {
    final locator = switch (io.Platform.isWindows) {
      true => 'where',
      false => 'which',
    };
    try {
      final result = await _context.shell.run(locator, [command]);
      if (result.exitCode != 0) return null;
      for (final line in result.stdout.split('\n')) {
        final path = line.trim();
        if (path.isNotEmpty && p.isAbsolute(path)) return p.normalize(path);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> verifyExecutable(String command, List<String> args) async {
    try {
      final result = await _context.shell.run(command, args);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _expandUserPath(String path) {
    if (!path.startsWith('~/') && !path.startsWith(r'~\')) {
      return path;
    }
    final home = io.Platform.environment['HOME'] ??
        io.Platform.environment['USERPROFILE'] ??
        '';
    if (home.isEmpty) {
      return path;
    }
    return p.join(home, path.substring(2));
  }

  /// Resolves execution command and arguments for Phpactor across system PATH,
  /// Composer global installations, package managers, and Lumide-managed plugin storage.
  Future<({String command, List<String> args})?>
      _resolvePhpactorExecution() async {
    final php = _phpService?.phpExecutable ?? 'php';

    // 1. Check Lumide-managed plugin storage directory
    try {
      final rawStorageDir = await _context.workspace.getPluginStorageDir();
      final storageDir = normalizeFilePath(rawStorageDir);
      final pharPath = p.join(storageDir, 'phpactor.phar');
      if (await _context.fs.exists(pharPath)) {
        final ok = await verifyExecutable(php, [pharPath, '--version']);
        if (ok) {
          return (command: php, args: [pharPath, 'language-server']);
        }
      }
    } catch (_) {}

    // 2. Check system executables on PATH or user folders
    final home = io.Platform.environment['USERPROFILE'] ??
        io.Platform.environment['HOME'] ??
        '';
    final appData = io.Platform.environment['APPDATA'] ?? '';
    final localAppData = io.Platform.environment['LOCALAPPDATA'] ?? '';

    final candidatePaths = [
      defaultPhpactorCommand,
      if (io.Platform.isWindows) ...[
        'phpactor.bat',
        'phpactor.cmd',
        if (appData.isNotEmpty)
          p.join(appData, 'Composer', 'vendor', 'bin', 'phpactor.bat'),
        if (localAppData.isNotEmpty)
          p.join(localAppData, 'Programs', 'phpactor', 'phpactor.bat'),
        if (home.isNotEmpty) ...[
          p.join(home, 'AppData', 'Roaming', 'Composer', 'vendor', 'bin',
              'phpactor.bat'),
          p.join(home, '.local', 'bin', 'phpactor.bat'),
          p.join(home, '.local', 'bin', 'phpactor'),
        ],
      ] else ...[
        _expandUserPath('~/.local/bin/phpactor'),
        _expandUserPath('~/.composer/vendor/bin/phpactor'),
        _expandUserPath('~/.config/composer/vendor/bin/phpactor'),
        '/usr/local/bin/phpactor',
        '/opt/homebrew/bin/phpactor',
        '/usr/bin/phpactor',
      ],
    ];

    for (final candidate in candidatePaths) {
      final executable = await findExecutable(candidate);
      if (executable != null) {
        return (command: executable, args: const ['language-server']);
      }
    }

    return null;
  }
}

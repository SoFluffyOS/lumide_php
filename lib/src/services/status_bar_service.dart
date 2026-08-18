/// Status bar item service for Lumide PHP.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/models/models.dart';
import 'package:path/path.dart' as p;

class PhpStatusBarService {
  PhpStatusBarService(this._context);

  final LumideContext _context;
  bool _serverItemCreated = false;
  String? _iconPath;

  /// Initializes status bar items.
  Future<void> init() async {
    _iconPath = await _resolveAssetPath(assetPhpLogo);

    await _context.statusBar.createItem(
      id: statusBarPhpId,
      text: '',
      iconPath: _iconPath,
      iconName: _iconPath == null ? iconCode : null,
      alignment: 'right',
      priority: 85,
      tooltip: 'PHP Tools & Language Server Menu',
      command: cmdPhpToolsMenu,
    );
  }

  /// Updates the PHP version and active LSP in the status bar tooltip.
  Future<void> updatePhpStatus({
    String? phpVersion,
    String? lspEngine,
  }) async {
    final tooltip = switch ((phpVersion, lspEngine)) {
      (final v?, final e?) => '$v ($e) — Click for PHP Tools',
      (final v?, null) => '$v — Click for PHP Tools',
      (null, final e?) => 'PHP ($e) — Click for PHP Tools',
      _ => 'PHP Tools & Language Server Menu',
    };

    await _context.statusBar.updateItem(
      statusBarPhpId,
      text: '',
      iconPath: _iconPath,
      iconName: _iconPath == null ? iconCode : null,
      tooltip: tooltip,
      command: cmdPhpToolsMenu,
    );
  }

  Future<String?> _resolveAssetPath(String assetName) async {
    try {
      final baseUri = Uri.parse('package:lumide_php/lumide_php.dart');
      final resolvedBase = await Isolate.resolvePackageUri(baseUri);

      if (resolvedBase != null && resolvedBase.isScheme('file')) {
        final libDir = p.dirname(resolvedBase.toFilePath());
        final packageRoot = p.dirname(libDir);
        final assetPath = p.normalize(
          p.join(packageRoot, folderAssets, assetName),
        );

        if (await File(assetPath).exists()) {
          return assetPath;
        }
      }
    } catch (_) {}

    final scriptPath = Platform.script.toFilePath();
    final scriptDir = p.dirname(scriptPath);

    final candidates = [
      p.join(scriptDir, '..', folderAssets, assetName),
      p.join(scriptDir, folderAssets, assetName),
      p.join(Directory.current.path, folderAssets, assetName),
    ];

    for (final candidate in candidates) {
      final normalized = p.normalize(candidate);
      if (await File(normalized).exists()) {
        return normalized;
      }
    }

    return null;
  }

  /// Updates the Dev Server indicator in the status bar.
  Future<void> updateDevServerStatus(
      bool isRunning, PhpServerConfig config) async {
    if (!isRunning) {
      if (_serverItemCreated) {
        await _context.statusBar.disposeItem(statusBarServerId);
        _serverItemCreated = false;
      }
      return;
    }

    final tooltip = 'PHP Dev Server on ${config.url} (Click to open)';

    if (_serverItemCreated) {
      await _context.statusBar.updateItem(
        statusBarServerId,
        text: ':${config.port}',
        iconName: iconGlobe,
        tooltip: tooltip,
        command: cmdPhpServerOpenBrowser,
      );
      return;
    }

    await _context.statusBar.createItem(
      id: statusBarServerId,
      text: ':${config.port}',
      iconName: iconGlobe,
      alignment: 'right',
      priority: 84,
      tooltip: tooltip,
      command: cmdPhpServerOpenBrowser,
    );
    _serverItemCreated = true;
  }

  /// Disposes status bar items.
  Future<void> dispose() async {
    await _context.statusBar.disposeItem(statusBarPhpId);
    if (_serverItemCreated) {
      await _context.statusBar.disposeItem(statusBarServerId);
      _serverItemCreated = false;
    }
  }
}

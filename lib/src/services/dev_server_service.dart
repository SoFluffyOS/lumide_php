/// PHP built-in web server management service.
library;

import 'dart:async';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/models/models.dart';
import 'package:lumide_php/src/services/log_service.dart';
import 'package:lumide_php/src/services/php_service.dart';
import 'package:lumide_php/src/utils/utils.dart';
import 'package:path/path.dart' as p;

class PhpDevServerService {
  PhpDevServerService(this._context, this._phpService, this._logger) {
    _bindProcessListeners();
  }

  final LumideContext _context;
  final PhpService _phpService;
  final LogService _logger;

  int? _serverPid;
  bool _isStarting = false;
  PhpServerConfig _config = const PhpServerConfig();
  LumideOutputChannel? _outputChannel;

  void Function(bool isRunning, PhpServerConfig config)? onStateChanged;

  bool get isRunning => _serverPid != null;
  bool get isStarting => _isStarting;
  PhpServerConfig get config => _config;

  /// Binds process lifecycle listeners once to avoid duplicate callback memory accumulation.
  void _bindProcessListeners() {
    _context.shell.onStdout((outPid, data) {
      if (outPid == _serverPid) {
        final ch = _outputChannel;
        if (ch case final c?) {
          unawaited(c.append(data));
        }
      }
    });

    _context.shell.onStderr((outPid, data) {
      if (outPid == _serverPid) {
        final ch = _outputChannel;
        if (ch case final c?) {
          unawaited(c.append(data));
        }
      }
    });

    _context.shell.onExit((exitPid, exitCode) {
      if (exitPid == _serverPid) {
        final ch = _outputChannel;
        if (ch case final c?) {
          unawaited(c.appendLine('PHP Server exited with code $exitCode'));
        }
        _serverPid = null;
        onStateChanged?.call(false, _config);
      }
    });
  }

  /// Initializes server configuration.
  Future<void> init() async {
    final host = await _context.workspace.getConfiguration(configDevServerHost);
    final port = await _context.workspace.getConfiguration(configDevServerPort);
    final docRoot = await _context.workspace.getConfiguration(
      configDevServerDocRoot,
    );

    final resolvedHost = switch (host) {
      final String h when h.trim().isNotEmpty => h.trim(),
      _ => '127.0.0.1',
    };

    final resolvedPort = switch (port) {
      final num n => n.toInt(),
      final String s => int.tryParse(s) ?? 8000,
      _ => 8000,
    };

    final resolvedDocRoot = switch (docRoot) {
      final String d => d.trim(),
      _ => '',
    };

    _config = PhpServerConfig(
      host: resolvedHost,
      port: resolvedPort,
      documentRoot: resolvedDocRoot,
    );
  }

  /// Starts the PHP built-in server.
  Future<void> start() async {
    if (!_phpService.hasPhp) {
      await _context.window.showMessage(
        'PHP CLI is not installed or not found on PATH. Configure "php.executablePath" in settings.',
        title: 'PHP Dev Server',
        type: MessageType.error,
      );
      return;
    }

    if (isRunning || _isStarting) {
      await _context.window.showMessage(
        'PHP Dev Server is already running or starting on ${_config.url}',
        title: 'PHP Dev Server',
        type: MessageType.info,
      );
      return;
    }

    _isStarting = true;
    try {
      await init();

      final root = await _context.workspace.getRootUri() ?? '';
      final normalizedRoot = root.isNotEmpty ? normalizeFilePath(root) : '';
      final docRootArg = _resolveDocRoot(normalizedRoot, _config.documentRoot);

      final args = [
        '-S',
        '${_config.host}:${_config.port}',
        if (docRootArg.isNotEmpty) ...['-t', docRootArg],
      ];

      _outputChannel ??=
          await _context.window.createOutputChannel('PHP Server');
      final channel = _outputChannel;
      if (channel case final ch?) {
        await ch.appendLine(
          'Starting PHP built-in server: ${_phpService.phpExecutable} ${args.join(' ')}',
        );
      }

      final pid = await _context.shell.spawn(
        _phpService.phpExecutable,
        args,
        workingDirectory: normalizedRoot.isNotEmpty ? normalizedRoot : null,
      );
      _serverPid = pid;

      onStateChanged?.call(true, _config);
      _logger.info('PHP Dev Server started on ${_config.url}');

      await _context.window.showMessage(
        'PHP Dev Server started on ${_config.url}',
        title: 'PHP Dev Server',
        type: MessageType.info,
      );
    } catch (e) {
      _logger.error('Failed to start PHP dev server', e);
      await _context.window.showMessage(
        'Failed to start PHP dev server: $e',
        title: 'PHP Dev Server',
        type: MessageType.error,
      );
    } finally {
      _isStarting = false;
    }
  }

  /// Stops the running PHP server.
  Future<void> stop() async {
    final pid = _serverPid;
    if (pid == null) {
      return;
    }

    try {
      await _context.shell.kill(pid);
      _serverPid = null;
      final ch = _outputChannel;
      if (ch case final c?) {
        await c.appendLine('PHP Server stopped.');
      }
      onStateChanged?.call(false, _config);

      await _context.window.showMessage(
        'PHP Dev Server stopped.',
        title: 'PHP Dev Server',
        type: MessageType.info,
      );
    } catch (e) {
      _logger.error('Failed to stop PHP dev server', e);
    }
  }

  /// Restarts the PHP built-in server.
  Future<void> restart() async {
    if (isRunning) {
      await stop();
    }
    await start();
  }

  /// Opens the active server URL in the default browser using the cross-platform window API.
  Future<void> openInBrowser() async {
    if (!isRunning) {
      await start();
    }
    try {
      await _context.window.openUrl(_config.url);
    } catch (e) {
      _logger.error('Failed to open browser', e);
    }
  }

  String _resolveDocRoot(String workspaceRoot, String configuredDocRoot) {
    if (configuredDocRoot.isNotEmpty) {
      if (p.isAbsolute(configuredDocRoot)) {
        return configuredDocRoot;
      }
      if (workspaceRoot.isNotEmpty) {
        return p.join(workspaceRoot, configuredDocRoot);
      }
      return configuredDocRoot;
    }
    return workspaceRoot;
  }
}

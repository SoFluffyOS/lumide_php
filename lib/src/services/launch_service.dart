/// Launch provider service leveraging the Lumide Run API.
library;

import 'dart:async';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/services/composer_service.dart';
import 'package:lumide_php/src/services/dev_server_service.dart';
import 'package:lumide_php/src/services/log_service.dart';
import 'package:lumide_php/src/services/php_service.dart';
import 'package:lumide_php/src/services/test_runner_service.dart';
import 'package:lumide_php/src/utils/utils.dart';
import 'package:path/path.dart' as p;

class PhpLaunchService {
  PhpLaunchService(
    this._context,
    this._phpService,
    this._devServerService,
    this._testRunnerService,
    this._composerService,
    this._logger,
  );

  final LumideContext _context;
  final PhpService _phpService;
  final PhpDevServerService _devServerService;
  final PhpTestRunnerService _testRunnerService;
  final ComposerService _composerService;
  final LogService _logger;

  final Map<String, LumideOutputChannel> _outputChannels = {};
  LumideOutputChannel? _activeOutputChannel;
  int? _activeRunningPid;
  Completer<int>? _activeProcessCompleter;
  String? _selectedConfigId;
  bool _activeDevServerLaunch = false;

  bool get isProcessRunning => _activeRunningPid != null;

  /// Initializes the launch provider and registers with the Lumide Run API.
  Future<void> init() async {
    _bindShellListeners();
    _bindToolbarListeners();

    _context.launch.onResolveConfigurations(_resolveLaunchConfigurations);
    _context.launch.onConfigure(_handleConfigureRequest);
    _context.launch.onLaunch(_handleLaunchRequest);

    // Watch composer.json changes to dynamically update run targets
    _context.workspace.onDidSaveTextDocument((uri) {
      if (uri.endsWith('composer.json')) {
        unawaited(_updateConfigurations());
      }
    });

    // Update launch configurations when dev server state changes
    final prevCallback = _devServerService.onStateChanged;
    _devServerService.onStateChanged = (isRunning, config) {
      prevCallback?.call(isRunning, config);
      if (!isRunning && _activeDevServerLaunch) {
        _activeDevServerLaunch = false;
        unawaited(
          _context.launch.didEnd(
            const LumideLaunchEvent(
              providerId: launchProviderPhp,
              kind: LumideLaunchKind.run,
              configurationId: launchConfigDevServer,
              exitCode: 0,
            ),
          ),
        );
      }
      unawaited(_updateToolbarControls());
      unawaited(_updateConfigurations());
    };

    final initialConfigs = await _currentConfigurations();

    await _context.launch.registerProvider(
      id: launchProviderPhp,
      title: pluginName,
      workspacePatterns: const [
        'composer.json',
        'phpunit.xml',
        'phpunit.xml.dist',
        '*.php',
        '*.phtml',
      ],
      kinds: const [
        LumideLaunchKind.run,
        LumideLaunchKind.test,
      ],
      defaultKinds: const [
        LumideLaunchKind.run,
        LumideLaunchKind.test,
      ],
      icon: iconPlay,
      priority: 90,
    );

    if (initialConfigs.isNotEmpty) {
      await _context.launch.updateConfigurations(
        launchProviderPhp,
        initialConfigs,
      );
    }

    await _updateToolbarControls();
  }

  void _bindShellListeners() {
    _context.shell.onStdout((pid, data) {
      if (pid == _activeRunningPid) {
        _activeOutputChannel?.append(data);
      }
    });

    _context.shell.onStderr((pid, data) {
      if (pid == _activeRunningPid) {
        _activeOutputChannel?.append(data);
      }
    });

    _context.shell.onExit((pid, code) {
      if (pid == _activeRunningPid) {
        _activeOutputChannel
            ?.appendLine('\n[PHP] Process finished with exit code $code.');
        _activeRunningPid = null;
        if (_activeProcessCompleter case final c? when !c.isCompleted) {
          c.complete(code);
        }
        _activeProcessCompleter = null;
      }
    });
  }

  void _bindToolbarListeners() {
    _context.toolbar.onTap((id, position) async {
      switch (id) {
        case cmdPhpServerOpenBrowser:
          await _devServerService.openInBrowser();
        case cmdPhpServerRestart:
          await _devServerService.restart();
        default:
          break;
      }
    });
  }

  /// Registers only auxiliary non-standard toolbar buttons (matching lumide_flutter pattern).
  /// Primary Stop is handled natively by the IDE's launch toolbar button.
  Future<void> _updateToolbarControls() async {
    final serverRunning = _devServerService.isRunning;

    if (serverRunning) {
      await _context.toolbar.registerItem(
        id: cmdPhpServerOpenBrowser,
        icon: iconGlobe,
        tooltip: 'Open in Browser',
        alignment: ToolbarItemAlignment.right,
        priority: 100,
      );
      await _context.toolbar.registerItem(
        id: cmdPhpServerRestart,
        icon: iconRefresh,
        tooltip: 'Restart Server',
        alignment: ToolbarItemAlignment.right,
        priority: 99,
      );
    } else {
      await _context.toolbar.unregisterItem(cmdPhpServerOpenBrowser);
      await _context.toolbar.unregisterItem(cmdPhpServerRestart);
    }
  }

  Future<List<LumideLaunchConfiguration>> _resolveLaunchConfigurations(
    LumideLaunchResolveRequest request,
  ) async {
    if (request.providerId != launchProviderPhp) {
      return const [];
    }
    return _currentConfigurations();
  }

  Future<LumideLaunchConfiguration?> _handleConfigureRequest(
    LumideLaunchConfigureRequest request,
  ) async {
    if (request.providerId != launchProviderPhp) {
      return null;
    }

    if (request.actionId == 'stop') {
      await stop();
      return request.configuration;
    }

    if (request.configuration case final config?) {
      _selectedConfigId = config.id;
      await _updateConfigurations();
    }
    return request.configuration;
  }

  Future<List<LumideLaunchConfiguration>> _currentConfigurations() async {
    final serverRunning = _devServerService.isRunning;

    final configs = <LumideLaunchConfiguration>[
      LumideLaunchConfiguration(
        id: launchConfigDevServer,
        label: 'PHP Built-in Server',
        kind: LumideLaunchKind.run,
        description: switch (serverRunning) {
          true => 'Running on ${_devServerService.config.url}',
          false =>
            '${_devServerService.config.host}:${_devServerService.config.port}',
        },
        detail:
            'php -S ${_devServerService.config.host}:${_devServerService.config.port}',
        icon: iconGlobe,
        isDefault: _selectedConfigId == launchConfigDevServer,
      ),
      LumideLaunchConfiguration(
        id: launchConfigTestAll,
        label: 'Run All Tests (Pest / PHPUnit)',
        kind: LumideLaunchKind.test,
        detail: 'Run complete test suite in workspace',
        icon: iconTest,
        isDefault: _selectedConfigId == launchConfigTestAll,
      ),
      LumideLaunchConfiguration(
        id: launchConfigTestActive,
        label: 'Run Current Test File',
        kind: LumideLaunchKind.test,
        detail: 'Run tests for active editor document',
        icon: iconTest,
        isDefault: _selectedConfigId == launchConfigTestActive,
      ),
      LumideLaunchConfiguration(
        id: launchConfigRunActiveFile,
        label: 'Run Active PHP File',
        kind: LumideLaunchKind.run,
        detail: 'Execute currently active PHP script',
        icon: iconFileCode,
        isDefault: _selectedConfigId == launchConfigRunActiveFile,
      ),
    ];

    // Include Composer scripts in Run Targets
    final manifest = await _composerService.getManifest();
    if (manifest case final m? when m.scripts.isNotEmpty) {
      for (final entry in m.scripts.entries) {
        final scriptName = entry.key;
        final commandDetail = switch (entry.value) {
          final List list => list.join(' && '),
          final v => v.toString(),
        };
        final scriptId = 'composer.script.$scriptName';
        configs.add(
          LumideLaunchConfiguration(
            id: scriptId,
            label: scriptName,
            description: 'composer script',
            kind: LumideLaunchKind.run,
            detail: switch (commandDetail.isNotEmpty) {
              true => commandDetail,
              false => 'composer run-script $scriptName',
            },
            icon: iconTerminal,
            isDefault: _selectedConfigId == scriptId,
          ),
        );
      }
    }

    return configs;
  }

  Future<void> _updateConfigurations() async {
    final configs = await _currentConfigurations();
    await _context.launch.updateConfigurations(launchProviderPhp, configs);
  }

  Future<void> _handleLaunchRequest(LumideLaunchRequest request) async {
    if (request.providerId != launchProviderPhp) {
      return;
    }

    final configId = request.configuration.id;
    final kind = request.kind;
    _selectedConfigId = configId;

    await _context.launch.didStart(
      LumideLaunchEvent(
        providerId: launchProviderPhp,
        kind: kind,
        configurationId: configId,
      ),
    );

    int exitCode = 0;
    try {
      if (configId == launchConfigDevServer) {
        if (_devServerService.isRunning) {
          await _devServerService.stop();
        } else {
          await _devServerService.start();
          if (_devServerService.isRunning) {
            _activeDevServerLaunch = true;
            // Launch session remains active; didEnd fires via onStateChanged when stopped.
            await _updateConfigurations();
            await _updateToolbarControls();
            return;
          } else {
            exitCode = 1;
          }
        }
      } else if (configId.startsWith('composer.script.')) {
        final scriptName = configId.substring('composer.script.'.length);
        exitCode = await _runComposerScriptProcess(scriptName);
      } else {
        exitCode = switch (configId) {
          launchConfigTestAll => await runTestsProcess(all: true),
          launchConfigTestActive => await runTestsProcess(all: false),
          launchConfigRunActiveFile => await runActivePhpFile(),
          _ => switch (kind) {
              LumideLaunchKind.test => await runTestsProcess(all: true),
              _ => await runActivePhpFile(),
            },
        };
      }
    } catch (e) {
      _logger.error('Launch request execution failed: $configId', e);
      exitCode = 1;
    } finally {
      await _context.launch.didEnd(
        LumideLaunchEvent(
          providerId: launchProviderPhp,
          kind: kind,
          configurationId: configId,
          exitCode: exitCode,
        ),
      );

      await _updateConfigurations();
      await _updateToolbarControls();
    }
  }

  /// Runs a Composer script through the launch process pipeline.
  Future<int> _runComposerScriptProcess(String scriptName) async {
    if (isProcessRunning) {
      await stopActiveProcess();
    }

    final channel = await _getOrCreateOutputChannel('Composer');
    await channel.show();
    await channel.clear();
    await channel.appendLine('[Composer] Running script: $scriptName\n');

    final completer = Completer<int>();
    _activeProcessCompleter = completer;

    final root = await _context.workspace.getRootUri() ?? '';
    final normalizedRoot = root.isNotEmpty ? normalizeFilePath(root) : '';
    final args = [
      if (normalizedRoot.isNotEmpty) ...['--working-dir', normalizedRoot],
      'run-script',
      scriptName,
    ];

    try {
      final pid = await _context.shell.spawn(
        _composerService.composerExecutable,
        args,
        workingDirectory: normalizedRoot.isNotEmpty ? normalizedRoot : null,
      );
      _activeRunningPid = pid;

      return await completer.future;
    } catch (e) {
      await channel.appendLine('\n[Composer] Error running script: $e');
      if (!completer.isCompleted) {
        completer.complete(1);
      }
      _activeProcessCompleter = null;
      return 1;
    }
  }

  /// Runs the currently active PHP script and streams output.
  Future<int> runActivePhpFile([String? targetFile]) async {
    if (!_phpService.hasPhp) {
      await _context.window.showMessage(
        'PHP CLI is not installed or not found on PATH. Configure "php.executablePath" in settings.',
        title: pluginName,
        type: MessageType.error,
      );
      return 1;
    }

    if (isProcessRunning) {
      await stopActiveProcess();
    }

    final rawFile = targetFile ?? await _context.editor.getActiveDocumentUri();
    if (rawFile == null) {
      await _context.window.showMessage(
        'No PHP file selected to run.',
        title: pluginName,
        type: MessageType.warning,
      );
      return 1;
    }
    final activeFile = normalizeFilePath(rawFile);

    final channel = await _getOrCreateOutputChannel('PHP Run');
    await channel.show();
    await channel.clear();
    await channel.appendLine('[PHP] Running: $activeFile\n');

    final completer = Completer<int>();
    _activeProcessCompleter = completer;

    final root = await _context.workspace.getRootUri() ?? '';
    final normalizedRoot = root.isNotEmpty ? normalizeFilePath(root) : '';
    final workingDir =
        normalizedRoot.isNotEmpty ? normalizedRoot : p.dirname(activeFile);

    try {
      final pid = await _context.shell.spawn(
        _phpService.phpExecutable,
        [activeFile],
        workingDirectory: workingDir.isNotEmpty ? workingDir : null,
      );
      _activeRunningPid = pid;

      return await completer.future;
    } catch (e) {
      await channel.appendLine('\n[PHP] Error executing file: $e');
      if (!completer.isCompleted) {
        completer.complete(1);
      }
      _activeProcessCompleter = null;
      return 1;
    }
  }

  /// Runs Pest or PHPUnit test suite and streams output to the dedicated output channel.
  Future<int> runTestsProcess({
    required bool all,
    String? targetFile,
  }) async {
    if (isProcessRunning) {
      await stopActiveProcess();
    }

    final runner = await _testRunnerService.resolveTestRunner();
    if (runner == null) {
      await _context.window.showMessage(
        'Neither Pest nor PHPUnit was found in vendor/bin or PATH.\n'
        'Install Pest: composer require --dev pestphp/pest\n'
        'Install PHPUnit: composer require --dev phpunit/phpunit',
        title: 'PHP Tests',
        type: MessageType.warning,
      );
      return 1;
    }

    List<String> args = const [];
    if (!all) {
      final rawFile =
          targetFile ?? await _context.editor.getActiveDocumentUri();
      if (rawFile == null) {
        await _context.window.showMessage(
          'No test file selected to run tests for.',
          title: 'PHP Tests',
          type: MessageType.warning,
        );
        return 1;
      }
      args = [normalizeFilePath(rawFile)];
    }

    final channel = await _getOrCreateOutputChannel('PHP Tests');
    await channel.show();
    await channel.clear();
    await channel.appendLine(
      '[PHP Test] Running $runner ${args.join(' ')}\n',
    );

    final completer = Completer<int>();
    _activeProcessCompleter = completer;

    final root = await _context.workspace.getRootUri() ?? '';
    final normalizedRoot = root.isNotEmpty ? normalizeFilePath(root) : '';

    try {
      final pid = await _context.shell.spawn(
        runner,
        args,
        workingDirectory: normalizedRoot.isNotEmpty ? normalizedRoot : null,
      );
      _activeRunningPid = pid;

      return await completer.future;
    } catch (e) {
      await channel.appendLine('\n[PHP Test] Failed to run test runner: $e');
      if (!completer.isCompleted) {
        completer.complete(1);
      }
      _activeProcessCompleter = null;
      return 1;
    }
  }

  /// Stops any currently active PHP test runner, Composer script, or script execution.
  Future<void> stopActiveProcess() async {
    final pid = _activeRunningPid;
    if (pid == null) {
      return;
    }

    try {
      await _context.shell.kill(pid);
      await _activeOutputChannel
          ?.appendLine('\n[PHP] Process cancelled by user.');
      _activeRunningPid = null;

      if (_activeProcessCompleter case final c? when !c.isCompleted) {
        c.complete(-1);
      }
      _activeProcessCompleter = null;

      await _context.window.showMessage(
        'PHP execution stopped.',
        title: pluginName,
        type: MessageType.info,
      );
    } catch (e) {
      _logger.error('Failed to stop process $pid', e);
    }
  }

  /// Unified stop method for IDE commands.
  Future<void> stop() async {
    if (isProcessRunning) {
      await stopActiveProcess();
    }
    if (_devServerService.isRunning) {
      await _devServerService.stop();
    }
  }

  Future<LumideOutputChannel> _getOrCreateOutputChannel(String name) async {
    final existing = _outputChannels[name];
    if (existing case final ch?) {
      _activeOutputChannel = ch;
      return ch;
    }
    final created = await _context.window.createOutputChannel(name);
    _outputChannels[name] = created;
    _activeOutputChannel = created;
    return created;
  }

  Future<void> dispose() async {
    await _context.launch.unregisterProvider(launchProviderPhp);
    await stop();
    if (_activeProcessCompleter case final c? when !c.isCompleted) {
      c.complete(-1);
    }
    _activeProcessCompleter = null;
    if (_activeDevServerLaunch) {
      _activeDevServerLaunch = false;
      await _context.launch.didEnd(
        const LumideLaunchEvent(
          providerId: launchProviderPhp,
          kind: LumideLaunchKind.run,
          configurationId: launchConfigDevServer,
          exitCode: 0,
        ),
      );
    }
    await _updateToolbarControls();
  }
}

/// LSP registration, installation, and lifecycle management service for PHP.
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/models/models.dart';
import 'package:lumide_php/src/services/log_service.dart';
import 'package:lumide_php/src/services/php_service.dart';
import 'package:lumide_php/src/utils/utils.dart';
import 'package:path/path.dart' as p;

class PhpLspService {
  PhpLspService(this._context, this._logger, [this._phpService]);

  final LumideContext _context;
  final LogService _logger;
  final PhpService? _phpService;

  LspServerType _activeServerType = LspServerType.auto;
  String _activeCommand = defaultIntelephenseCommand;
  List<String> _activeArgs = const ['--stdio'];
  bool _isRegistered = false;

  LspServerType get activeServerType => _activeServerType;
  String get activeCommand => _activeCommand;
  bool get isRegistered => _isRegistered;

  /// Initializes and registers the PHP language server.
  Future<bool> init() async {
    final configuredServer = await _context.workspace.getConfiguration(
      configLspServer,
    );
    final serverType = LspServerType.fromString(
      configuredServer as String?,
    );

    final resolved = await _resolveLspEngine(serverType);
    if (resolved == null) {
      _logger.warning('No PHP Language Server found on system');
      unawaited(
        _context.window.showMessage(
          'No PHP Language Server detected. Code completion and navigation are disabled.\n'
          'Click the PHP status bar item or open Tools Menu to install Intelephense or Phpactor.',
          title: pluginName,
          type: MessageType.warning,
        ),
      );
      return false;
    }

    _activeServerType = resolved.serverType;
    _activeCommand = resolved.command;
    _activeArgs = resolved.args;

    await _registerCurrentLsp();
    return true;
  }

  /// Registers or updates the active LSP server in Lumide.
  Future<void> _registerCurrentLsp() async {
    final initOptions = await _buildInitializationOptions();
    final providerId = switch (_activeServerType) {
      LspServerType.intelephense => lspProviderIdIntelephense,
      LspServerType.phpactor => lspProviderIdPhpactor,
      LspServerType.phpLanguageServer => lspProviderIdPhpLanguageServer,
      _ => lspProviderIdCustom,
    };

    await _context.languages.registerLanguageServer(
      id: providerId,
      languageId: phpLanguageId,
      displayName: _activeServerType.label,
      fileExtensions: phpFileExtensions,
      command: _activeCommand,
      args: _activeArgs,
      initializationOptions: initOptions,
    );

    _isRegistered = true;
    _logger.info(
      'Registered PHP LSP ($_activeCommand) with languageId "$phpLanguageId"',
    );
  }

  /// Restarts the active language server.
  Future<void> restartLsp() async {
    if (!_isRegistered) {
      await _context.window.showMessage(
        'No PHP Language Server is currently active. Use "PHP: Select Language Server" to configure one.',
        title: pluginName,
        type: MessageType.warning,
      );
      return;
    }
    await _registerCurrentLsp();
    await _context.window.showMessage(
      'PHP Language Server restarted ($_activeCommand)',
      title: pluginName,
      type: MessageType.info,
    );
  }

  /// Installs Intelephense via npm using shell after checking if already present.
  Future<void> installIntelephense() async {
    final ok = await _verifyExecutable(
      defaultIntelephenseCommand,
      const ['--version'],
    );
    if (ok) {
      _activeServerType = LspServerType.intelephense;
      _activeCommand = defaultIntelephenseCommand;
      _activeArgs = const ['--stdio'];
      await _registerCurrentLsp();
      await _context.window.showMessage(
        'Intelephense is already installed and has been activated.',
        title: 'Install Intelephense',
        type: MessageType.info,
      );
      return;
    }

    await _runShellInstaller(
      command: 'npm',
      args: const ['install', '-g', 'intelephense'],
      title: 'Install Intelephense',
      targetServerType: LspServerType.intelephense,
      targetCommand: defaultIntelephenseCommand,
      targetArgs: const ['--stdio'],
    );
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

  /// Installs Phpactor standalone PHAR into the Lumide-managed plugin storage directory.
  Future<void> installPhpactor() async {
    final hasPhp = _phpService?.hasPhp ?? false;
    if (!hasPhp) {
      await _context.window.showMessage(
        'PHP 8.2+ executable is required to run Phpactor standalone PHAR.\n'
        'Please install PHP or configure "$configPhpExecutable" in settings first.',
        title: 'Install Phpactor',
        type: MessageType.error,
      );
      return;
    }

    // 1. Check if user already has an installed Phpactor on system or in storage
    final existing = await _resolvePhpactorExecution();
    if (existing case final ex?) {
      _activeServerType = LspServerType.phpactor;
      _activeCommand = ex.command;
      _activeArgs = ex.args;
      await _registerCurrentLsp();
      await _context.window.showMessage(
        'Phpactor is already installed (${ex.command}) and has been activated.',
        title: 'Install Phpactor',
        type: MessageType.info,
      );
      return;
    }

    const pharUrl =
        'https://github.com/phpactor/phpactor/releases/latest/download/phpactor.phar';

    await _context.window.showMessage(
      'Downloading Phpactor standalone PHAR...',
      title: 'Install Phpactor',
      type: MessageType.info,
    );

    try {
      final rawStorageDir = await _context.workspace.getPluginStorageDir();
      final storageDir = normalizeFilePath(rawStorageDir);
      final targetPath = p.join(storageDir, 'phpactor.phar');
      final php = _phpService?.phpExecutable ?? 'php';

      // 2. Download PHAR using context.fs.downloadFile if available, or fallback to curl
      var downloaded = false;
      try {
        await _context.fs.downloadFile(
          pharUrl,
          targetPath,
          label: 'Downloading Phpactor Language Server...',
        );
        downloaded = await _context.fs.exists(targetPath);
      } catch (e) {
        _logger.warning('downloadFile failed, falling back to curl: $e');
      }

      if (!downloaded) {
        final curlRes = await _context.shell.run('curl', [
          '-Lo',
          targetPath,
          pharUrl,
        ]);
        if (curlRes.exitCode != 0) {
          final err = '${curlRes.stderr}\n${curlRes.stdout}'.trim();
          await _context.window.showMessage(
            'Failed to download Phpactor PHAR: $err',
            title: 'Install Phpactor',
            type: MessageType.error,
          );
          return;
        }
      }

      // 3. Verify installation using PHP CLI directly (works on Windows, macOS, Linux)
      final isExecutable =
          await _verifyExecutable(php, [targetPath, '--version']);
      if (!isExecutable) {
        await _context.window.showMessage(
          'Phpactor downloaded but failed verification. Ensure PHP 8.2+ is installed.',
          title: 'Install Phpactor',
          type: MessageType.error,
        );
        return;
      }

      _activeServerType = LspServerType.phpactor;
      _activeCommand = php;
      _activeArgs = [targetPath, 'language-server'];

      await _registerCurrentLsp();

      await _context.window.showMessage(
        'Phpactor standalone PHAR installed and activated successfully.',
        title: 'Install Phpactor',
        type: MessageType.info,
      );
    } catch (e) {
      _logger.error('Failed to install Phpactor standalone PHAR', e);
      await _context.window.showMessage(
        'Failed to install Phpactor: $e',
        title: 'Install Phpactor',
        type: MessageType.error,
      );
    }
  }

  /// Prompts the user to pick an LSP server engine and switches to it.
  Future<void> selectLsp([Object? args]) async {
    Map<String, int>? position;
    if (args case {'position': final Map posMap}) {
      if (posMap['x'] case final num x) {
        if (posMap['y'] case final num y) {
          position = {
            'x': x.toInt(),
            'y': y.toInt(),
          };
        }
      }
    }

    const items = [
      QuickPickItem(
        label: 'PHP language servers',
        enabled: false,
      ),
      QuickPickItem(
        label: '',
        isSeparator: true,
      ),
      QuickPickItem(
        label: 'Intelephense',
        tooltip: 'npm install -g intelephense',
        icon: iconCode,
        payload: 'intelephense',
      ),
      QuickPickItem(
        label: 'Phpactor',
        tooltip: 'phpactor language-server',
        icon: iconCode,
        payload: 'phpactor',
      ),
      QuickPickItem(
        label: 'PHP Language Server',
        tooltip: 'felixfbecker/php-language-server',
        icon: iconCode,
        payload: 'php-language-server',
      ),
      QuickPickItem(
        label: 'Custom Executable',
        tooltip: 'Configured binary path',
        icon: iconTerminal,
        payload: 'custom',
      ),
    ];

    final picked = await _context.window.showQuickPick(
      items,
      placeholder: 'Select PHP Language Server Engine',
      position: position,
    );

    if (picked == null) {
      return;
    }

    final serverType = switch (picked.payload) {
      final String id => LspServerType.fromString(id),
      final LspServerType t => t,
      _ => LspServerType.fromString(picked.label),
    };

    final resolved = await _resolveLspEngine(serverType);
    if (resolved == null) {
      await _context.window.showMessage(
        'Selected language server (${serverType.label}) is not installed or not working.',
        title: pluginName,
        type: MessageType.error,
      );
      return;
    }

    _activeServerType = resolved.serverType;
    _activeCommand = resolved.command;
    _activeArgs = resolved.args;

    await _registerCurrentLsp();
    await _context.window.showMessage(
      'Switched PHP Language Server to ${serverType.label}',
      title: pluginName,
      type: MessageType.info,
    );
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
        final ok = await _verifyExecutable(php, [pharPath, '--version']);
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
      if (await _verifyExecutable(candidate, const ['--version'])) {
        return (command: candidate, args: const ['language-server']);
      }
    }

    return null;
  }

  /// Resolves the command and args for a given [serverType].
  Future<({LspServerType serverType, String command, List<String> args})?>
      _resolveLspEngine(LspServerType serverType) async {
    // 1. Check custom path configuration
    final customPath = await _context.workspace.getConfiguration(configLspPath);
    if (customPath case final String path when path.trim().isNotEmpty) {
      final customCmd = path.trim();
      final ok = await _verifyExecutable(customCmd, const ['--version']);
      if (ok) {
        return (
          serverType: LspServerType.custom,
          command: customCmd,
          args: const <String>['--stdio'],
        );
      }
    }

    // 2. Specific requested server
    if (serverType == LspServerType.intelephense) {
      final ok = await _verifyExecutable(
        defaultIntelephenseCommand,
        const ['--version'],
      );
      if (ok) {
        return (
          serverType: LspServerType.intelephense,
          command: defaultIntelephenseCommand,
          args: const <String>['--stdio'],
        );
      }
      return null;
    }

    if (serverType == LspServerType.phpactor) {
      final exec = await _resolvePhpactorExecution();
      if (exec case final e?) {
        return (
          serverType: LspServerType.phpactor,
          command: e.command,
          args: e.args,
        );
      }
      return null;
    }

    if (serverType == LspServerType.phpLanguageServer) {
      final ok = await _verifyExecutable(
        defaultPhpLanguageServerCommand,
        const ['--version'],
      );
      if (ok) {
        return (
          serverType: LspServerType.phpLanguageServer,
          command: defaultPhpLanguageServerCommand,
          args: const <String>[],
        );
      }
      return null;
    }

    // 3. Auto-detection (intelephense -> phpactor -> php-language-server)
    final hasIntelephense = await _verifyExecutable(
      defaultIntelephenseCommand,
      const ['--version'],
    );
    if (hasIntelephense) {
      return (
        serverType: LspServerType.intelephense,
        command: defaultIntelephenseCommand,
        args: const <String>['--stdio'],
      );
    }

    final phpactorExec = await _resolvePhpactorExecution();
    if (phpactorExec case final e?) {
      return (
        serverType: LspServerType.phpactor,
        command: e.command,
        args: e.args,
      );
    }

    final hasPhpLs = await _verifyExecutable(
      defaultPhpLanguageServerCommand,
      const ['--version'],
    );
    if (hasPhpLs) {
      return (
        serverType: LspServerType.phpLanguageServer,
        command: defaultPhpLanguageServerCommand,
        args: const <String>[],
      );
    }

    return null;
  }

  Future<bool> _verifyExecutable(String command, List<String> args) async {
    try {
      final res = await _context.shell.run(command, args);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _buildInitializationOptions() async {
    final licence = await _context.workspace.getConfiguration(
      configIntelephenseLicence,
    );
    if (licence case final String key when key.trim().isNotEmpty) {
      return {'licenceKey': key.trim()};
    }
    return null;
  }

  Future<void> _runShellInstaller({
    required String command,
    required List<String> args,
    required String title,
    required LspServerType targetServerType,
    required String targetCommand,
    required List<String> targetArgs,
  }) async {
    await _context.window.showMessage(
      'Installing $title ($command ${args.join(' ')})...',
      title: title,
      type: MessageType.info,
    );

    try {
      final res = await _context.shell.run(command, args);
      if (res.exitCode == 0) {
        _activeServerType = targetServerType;
        _activeCommand = targetCommand;
        _activeArgs = targetArgs;

        await _registerCurrentLsp();

        await _context.window.showMessage(
          '$title completed successfully. Language server is now active.',
          title: title,
          type: MessageType.info,
        );
        return;
      }

      final errorMsg = '${res.stderr}\n${res.stdout}'.trim();
      _logger.error('Installation failed: $errorMsg');
      await _context.window.showMessage(
        'Failed to install ($title):\n$errorMsg',
        title: title,
        type: MessageType.error,
      );
    } catch (e) {
      _logger.error('Failed to execute shell installation', e);
      await _context.window.showMessage(
        'Failed to execute $title: $e',
        title: title,
        type: MessageType.error,
      );
    }
  }
}

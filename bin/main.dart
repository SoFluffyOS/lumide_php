/// PHP Language and Tooling plugin for Lumide IDE.
library;

import 'dart:async';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/lumide_php.dart';

void main() => PhpPlugin().run();

class PhpPlugin extends LumidePlugin {
  late final LogService logService;
  late final PhpService phpService;
  late final PhpLspService lspService;
  late final ComposerService composerService;
  late final PhpDevServerService devServerService;
  late final PhpTestRunnerService testRunnerService;
  late final PhpFormatterService formatterService;
  late final PhpStatusBarService statusBarService;
  late final PhpLaunchService launchService;

  @override
  Future<void> onActivate(LumideContext context) async {
    log('$logPrefix $pluginName plugin activating...');

    // 1. Initialize services
    logService = LogService(log);
    phpService = PhpService(context, logService);
    lspService = PhpLspService(context, logService, phpService);
    composerService = ComposerService(context, logService);
    devServerService = PhpDevServerService(context, phpService, logService);
    testRunnerService = PhpTestRunnerService(context, phpService, logService);
    formatterService = PhpFormatterService(context, phpService, logService);
    statusBarService = PhpStatusBarService(context);
    launchService = PhpLaunchService(
      context,
      phpService,
      devServerService,
      testRunnerService,
      composerService,
      logService,
    );

    testRunnerService.launchService = launchService;

    // 2. Wire state changes
    devServerService.onStateChanged = (isRunning, config) {
      unawaited(statusBarService.updateDevServerStatus(isRunning, config));
    };

    // 3. Initialize components
    await Future.wait([
      phpService.init(),
      composerService.init(),
      devServerService.init(),
      statusBarService.init(),
      launchService.init(),
    ]);

    // 4. Register LSP Language Server
    await lspService.init();

    // 5. Update Status Bar with PHP info
    await statusBarService.updatePhpStatus(
      phpVersion: phpService.phpVersion,
      lspEngine: lspService.isRegistered
          ? lspService.activeServerType.label
          : 'No LSP',
    );

    // 6. Register Commands
    await _registerCommands(context);

    // 7. Register Context Menu Actions
    await _registerMenuActions(context);

    log('$logPrefix $pluginName plugin successfully activated');
  }

  @override
  Future<void> onDeactivate() async {
    await devServerService.stop();
    await launchService.dispose();
    await statusBarService.dispose();
    log('$logPrefix $pluginName plugin deactivated');
  }

  Future<void> _registerCommands(LumideContext context) async {
    await context.commands.registerCommand(
      id: cmdPhpToolsMenu,
      title: 'PHP: Tools & Language Server Menu',
      category: pluginName,
      callback: ([args]) async => _showToolsMenu(context, args),
    );

    await context.commands.registerCommand(
      id: cmdPhpInstallIntelephense,
      title: 'PHP: Install Intelephense Language Server (npm)',
      category: pluginName,
      callback: ([args]) async {
        await lspService.installIntelephense();
        await statusBarService.updatePhpStatus(
          phpVersion: phpService.phpVersion,
          lspEngine: lspService.isRegistered
              ? lspService.activeServerType.label
              : 'No LSP',
        );
      },
    );

    await context.commands.registerCommand(
      id: cmdPhpInstallPhpactor,
      title: 'PHP: Install Phpactor Language Server (Standalone PHAR)',
      category: pluginName,
      callback: ([args]) async {
        await lspService.installPhpactor();
        await statusBarService.updatePhpStatus(
          phpVersion: phpService.phpVersion,
          lspEngine: lspService.isRegistered
              ? lspService.activeServerType.label
              : 'No LSP',
        );
      },
    );

    await context.commands.registerCommand(
      id: cmdPhpRestartLsp,
      title: 'PHP: Restart Language Server',
      category: pluginName,
      callback: ([args]) async => lspService.restartLsp(),
    );

    await context.commands.registerCommand(
      id: cmdPhpSelectLsp,
      title: 'PHP: Select Language Server',
      category: pluginName,
      callback: ([args]) async {
        await lspService.selectLsp(args);
        await statusBarService.updatePhpStatus(
          phpVersion: phpService.phpVersion,
          lspEngine: lspService.isRegistered
              ? lspService.activeServerType.label
              : 'No LSP',
        );
      },
    );

    await context.commands.registerCommand(
      id: cmdPhpNewFile,
      title: 'PHP: New PHP File',
      category: pluginName,
      callback: ([args]) async => phpService.newPhpFile(args),
    );

    await context.commands.registerCommand(
      id: cmdPhpRunFile,
      title: 'PHP: Run PHP File',
      category: pluginName,
      callback: ([args]) async =>
          launchService.runActivePhpFile(_pathFromContext(args)),
    );

    await context.commands.registerCommand(
      id: cmdPhpLintFile,
      title: 'PHP: Lint Active File (php -l)',
      category: pluginName,
      callback: ([args]) async => formatterService.lintActiveFile(args),
    );

    await context.commands.registerCommand(
      id: cmdPhpFormatFile,
      title: 'PHP: Format Active File (Pint / PHP-CS-Fixer)',
      category: pluginName,
      callback: ([args]) async => formatterService.formatActiveFile(args),
    );

    await context.commands.registerCommand(
      id: cmdPhpServerStart,
      title: 'PHP: Start Built-in Web Server',
      category: pluginName,
      callback: ([args]) async => devServerService.start(),
    );

    await context.commands.registerCommand(
      id: cmdPhpServerStop,
      title: 'PHP: Stop Built-in Web Server',
      category: pluginName,
      callback: ([args]) async => devServerService.stop(),
    );

    await context.commands.registerCommand(
      id: cmdPhpServerRestart,
      title: 'PHP: Restart Built-in Web Server',
      category: pluginName,
      callback: ([args]) async => devServerService.restart(),
    );

    await context.commands.registerCommand(
      id: cmdPhpServerOpenBrowser,
      title: 'PHP: Open Server in Browser',
      category: pluginName,
      callback: ([args]) async => devServerService.openInBrowser(),
    );

    await context.commands.registerCommand(
      id: cmdPhpStop,
      title: 'PHP: Stop Running Process',
      category: pluginName,
      callback: ([args]) async => launchService.stop(),
    );

    await context.commands.registerCommand(
      id: cmdPhpTestRunAll,
      title: 'PHP: Run All Tests (PHPUnit / Pest)',
      category: pluginName,
      callback: ([args]) async => testRunnerService.runAllTests(),
    );

    await context.commands.registerCommand(
      id: cmdPhpTestRunActiveFile,
      title: 'PHP: Run Current Test File',
      category: pluginName,
      callback: ([args]) async => testRunnerService.runActiveFile(args),
    );

    await context.commands.registerCommand(
      id: cmdComposerInstall,
      title: 'Composer: Install',
      category: 'Composer',
      callback: ([args]) async => composerService.install(),
    );

    await context.commands.registerCommand(
      id: cmdComposerUpdate,
      title: 'Composer: Update',
      category: 'Composer',
      callback: ([args]) async => composerService.update(),
    );

    await context.commands.registerCommand(
      id: cmdComposerDumpAutoload,
      title: 'Composer: Dump Autoload',
      category: 'Composer',
      callback: ([args]) async => composerService.dumpAutoload(),
    );

    await context.commands.registerCommand(
      id: cmdComposerValidate,
      title: 'Composer: Validate composer.json',
      category: 'Composer',
      callback: ([args]) async => composerService.validate(),
    );

    await context.commands.registerCommand(
      id: cmdComposerRequirePackage,
      title: 'Composer: Require Package',
      category: 'Composer',
      callback: ([args]) async => composerService.requirePackage(),
    );

    await context.commands.registerCommand(
      id: cmdComposerRunScript,
      title: 'Composer: Run Script...',
      category: 'Composer',
      callback: ([args]) async => composerService.runScript(args),
    );
  }

  Future<void> _registerMenuActions(LumideContext context) async {
    await Future.wait([
      // File Tree Context Menu
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_new_file_tree',
          title: 'New PHP File',
          command: cmdPhpNewFile,
          location: LumideMenuLocation.fileTreeItem,
          group: 'create',
          priority: 140,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_run_file_tree',
          title: 'Run PHP File',
          command: cmdPhpRunFile,
          location: LumideMenuLocation.fileTreeItem,
          group: 'php',
          priority: 120,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_format_file_tree',
          title: 'Format PHP File',
          command: cmdPhpFormatFile,
          location: LumideMenuLocation.fileTreeItem,
          group: 'php',
          priority: 110,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_lint_file_tree',
          title: 'Lint PHP File',
          command: cmdPhpLintFile,
          location: LumideMenuLocation.fileTreeItem,
          group: 'php',
          priority: 100,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_test_file_tree',
          title: 'Run PHP Tests',
          command: cmdPhpTestRunActiveFile,
          location: LumideMenuLocation.fileTreeItem,
          group: 'php',
          priority: 90,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'composer_install_tree',
          title: 'Composer: Install',
          command: cmdComposerInstall,
          location: LumideMenuLocation.fileTreeItem,
          group: 'composer',
          priority: 80,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'composer_update_tree',
          title: 'Composer: Update',
          command: cmdComposerUpdate,
          location: LumideMenuLocation.fileTreeItem,
          group: 'composer',
          priority: 70,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'composer_dump_tree',
          title: 'Composer: Dump Autoload',
          command: cmdComposerDumpAutoload,
          location: LumideMenuLocation.fileTreeItem,
          group: 'composer',
          priority: 60,
        ),
      ),

      // Editor Context Menu
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_format_editor',
          title: 'Format PHP Document',
          command: cmdPhpFormatFile,
          location: LumideMenuLocation.editor,
          group: 'php',
          priority: 100,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_lint_editor',
          title: 'Lint PHP Document',
          command: cmdPhpLintFile,
          location: LumideMenuLocation.editor,
          group: 'php',
          priority: 90,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_run_editor',
          title: 'Run PHP Script',
          command: cmdPhpRunFile,
          location: LumideMenuLocation.editor,
          group: 'php',
          priority: 80,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_test_editor',
          title: 'Run PHP Tests',
          command: cmdPhpTestRunActiveFile,
          location: LumideMenuLocation.editor,
          group: 'php',
          priority: 70,
        ),
      ),

      // Tab Bar Context Menu
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_format_tab',
          title: 'Format PHP File',
          command: cmdPhpFormatFile,
          location: LumideMenuLocation.tabBarItem,
          group: 'php',
          priority: 100,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'php_lint_tab',
          title: 'Lint PHP File',
          command: cmdPhpLintFile,
          location: LumideMenuLocation.tabBarItem,
          group: 'php',
          priority: 90,
        ),
      ),
    ]);
  }

  String? _pathFromContext(Object? args) {
    if (args == null) {
      return null;
    }
    if (args case final String s when s.isNotEmpty) {
      return normalizeFilePath(s);
    }
    if (args case {'context': {'primary': {'path': final String p}}}
        when p.isNotEmpty) {
      return normalizeFilePath(p);
    }
    if (args case {'path': final String p} when p.isNotEmpty) {
      return normalizeFilePath(p);
    }
    if (args case {'uri': final String u} when u.isNotEmpty) {
      return normalizeFilePath(u);
    }
    return null;
  }

  Future<void> _showToolsMenu(LumideContext context, [Object? args]) async {
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

    final lspLabel =
        lspService.isRegistered ? lspService.activeServerType.label : 'No LSP';
    final versionHeader = switch (phpService.phpVersion) {
      final v? => '$v ($lspLabel)',
      _ => 'PHP: Not Detected ($lspLabel)',
    };

    final items = [
      // Top Header: PHP Version & LSP Engine
      QuickPickItem(
        label: versionHeader,
        enabled: false,
      ),

      // Section: Language server
      const QuickPickItem(
        label: '',
        isSeparator: true,
      ),
      const QuickPickItem(
        label: 'Language server',
        enabled: false,
      ),
      const QuickPickItem(
        label: 'Install Intelephense (npm)',
        tooltip: 'Install Intelephense globally via npm',
        icon: iconDownload,
        payload: 'install_intelephense',
      ),
      const QuickPickItem(
        label: 'Install Phpactor (Standalone PHAR)',
        tooltip: 'Download and install standalone phpactor.phar',
        icon: iconDownload,
        payload: 'install_phpactor',
      ),
      const QuickPickItem(
        label: 'Switch Language Server',
        tooltip: 'Select active PHP language server engine',
        icon: iconSwitch,
        payload: 'select_lsp',
      ),
      const QuickPickItem(
        label: 'Restart Language Server',
        tooltip: 'Restart active PHP language server',
        icon: iconRefresh,
        payload: 'restart_lsp',
      ),

      // Section: Composer
      const QuickPickItem(
        label: '',
        isSeparator: true,
      ),
      const QuickPickItem(
        label: 'Composer',
        enabled: false,
      ),
      const QuickPickItem(
        label: 'Install Dependencies',
        tooltip: 'composer install',
        icon: iconPackage,
        payload: 'composer_install',
      ),
      const QuickPickItem(
        label: 'Update Dependencies',
        tooltip: 'composer update',
        icon: iconPackageCheck,
        payload: 'composer_update',
      ),
      const QuickPickItem(
        label: 'Dump Autoload',
        tooltip: 'composer dump-autoload -o',
        icon: iconPackage,
        payload: 'composer_dump',
      ),
      const QuickPickItem(
        label: 'Require Package...',
        tooltip: 'composer require <package>',
        icon: iconPackagePlus,
        payload: 'composer_require',
      ),
      const QuickPickItem(
        label: 'Run Script...',
        tooltip: 'composer run-script <script>',
        icon: iconTerminal,
        payload: 'composer_script',
      ),

      // Section: Code quality
      const QuickPickItem(
        label: '',
        isSeparator: true,
      ),
      const QuickPickItem(
        label: 'Code quality',
        enabled: false,
      ),
      const QuickPickItem(
        label: 'Format Active File',
        tooltip: 'Format file using Pint or PHP-CS-Fixer',
        icon: iconFormat,
        payload: 'format_file',
      ),
      const QuickPickItem(
        label: 'Lint Active File',
        tooltip: 'php -l <file>',
        icon: iconLint,
        payload: 'lint_file',
      ),
    ];

    final picked = await context.window.showQuickPick(
      items,
      placeholder: 'PHP Tools & Language Server Menu',
      position: position,
    );

    if (picked == null) {
      return;
    }

    switch (picked.payload) {
      case 'install_intelephense':
        await lspService.installIntelephense();
        await statusBarService.updatePhpStatus(
          phpVersion: phpService.phpVersion,
          lspEngine: lspService.isRegistered
              ? lspService.activeServerType.label
              : 'No LSP',
        );
      case 'install_phpactor':
        await lspService.installPhpactor();
        await statusBarService.updatePhpStatus(
          phpVersion: phpService.phpVersion,
          lspEngine: lspService.isRegistered
              ? lspService.activeServerType.label
              : 'No LSP',
        );
      case 'select_lsp':
        await lspService.selectLsp(args);
        await statusBarService.updatePhpStatus(
          phpVersion: phpService.phpVersion,
          lspEngine: lspService.isRegistered
              ? lspService.activeServerType.label
              : 'No LSP',
        );
      case 'restart_lsp':
        await lspService.restartLsp();
      case 'composer_install':
        await composerService.install();
      case 'composer_update':
        await composerService.update();
      case 'composer_dump':
        await composerService.dumpAutoload();
      case 'composer_require':
        await composerService.requirePackage();
      case 'composer_script':
        await composerService.runScript(args);
      case 'format_file':
        await formatterService.formatActiveFile();
      case 'lint_file':
        await formatterService.lintActiveFile();
      default:
        break;
    }
  }
}

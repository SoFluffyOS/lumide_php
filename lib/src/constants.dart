/// Constants for the Lumide PHP plugin.
library;

// Plugin Metadata
const pluginId = 'lumide_php';
const pluginName = 'PHP';
const logPrefix = '[PHP]';

// Asset Paths
const folderAssets = 'assets';
const assetPhpLogo = 'php-logo.svg';

// Language IDs & File Extensions
const phpLanguageId = 'php';
const phpFileExtensions = [
  '.php',
  '.phtml',
  '.php4',
  '.php5',
  '.php7',
  '.php8',
  '.inc',
  '.stub',
];

// LSP Commands & Defaults
const defaultIntelephenseCommand = 'intelephense';
const defaultPhpactorCommand = 'phpactor';
const defaultPhpLanguageServerCommand = 'php-language-server';

const lspProviderIdIntelephense = 'php-intelephense';
const lspProviderIdPhpactor = 'php-phpactor';
const lspProviderIdPhpLanguageServer = 'php-language-server';
const lspProviderIdCustom = 'php-custom';

// Configuration Keys
const configLspServer = 'php.lsp.server';
const configLspPath = 'php.lsp.path';
const configPhpExecutable = 'php.executablePath';
const configComposerPath = 'php.composer.path';
const configDevServerHost = 'php.devServer.host';
const configDevServerPort = 'php.devServer.port';
const configDevServerDocRoot = 'php.devServer.documentRoot';
const configIntelephenseLicence = 'php.intelephense.licenceKey';

// Commands
const cmdPhpToolsMenu = 'php.toolsMenu';
// Existing command IDs now expose status and discovery; Lumide owns lifecycle controls.
const cmdPhpRestartLsp = 'php.restartLsp';
const cmdPhpSelectLsp = 'php.selectLsp';
const cmdPhpInstallIntelephense = 'php.installIntelephense';
const cmdPhpInstallPhpactor = 'php.installPhpactor';
const cmdPhpLintFile = 'php.lintFile';
const cmdPhpFormatFile = 'php.formatFile';
const cmdPhpServerStart = 'php.server.start';
const cmdPhpServerStop = 'php.server.stop';
const cmdPhpServerRestart = 'php.server.restart';
const cmdPhpServerOpenBrowser = 'php.server.openBrowser';
const cmdPhpStop = 'php.stop';
const cmdPhpNewFile = 'php.newFile';
const cmdPhpRunFile = 'php.runFile';
const cmdPhpTestRunAll = 'php.test.runAll';
const cmdPhpTestRunActiveFile = 'php.test.runActiveFile';

const cmdComposerInstall = 'composer.install';
const cmdComposerUpdate = 'composer.update';
const cmdComposerDumpAutoload = 'composer.dumpAutoload';
const cmdComposerValidate = 'composer.validate';
const cmdComposerRequirePackage = 'composer.requirePackage';
const cmdComposerRunScript = 'composer.runScript';

// Launch Provider IDs & Configs
const launchProviderPhp = 'php';
const launchConfigDevServer = 'php.devServer';
const launchConfigRunActiveFile = 'php.runActiveFile';
const launchConfigTestAll = 'php.test.all';
const launchConfigTestActive = 'php.test.active';

// Status Bar IDs
const statusBarPhpId = 'lumide_php.status';
const statusBarServerId = 'lumide_php.devServer';

// Lucide Icon Names (from lucideIconMap)
const iconCode = 'code';
const iconFileCode = 'file-code';
const iconGlobe = 'globe';
const iconDownload = 'download';
const iconRefresh = 'rotate-cw';
const iconSwitch = 'arrow-left-right';
const iconPackage = 'package';
const iconPackagePlus = 'package-plus';
const iconPackageCheck = 'package-check';
const iconTerminal = 'terminal';
const iconPlay = 'play';
const iconSquare = 'square';
const iconTest = 'flask-conical';
const iconFormat = 'paintbrush';
const iconLint = 'circle-check';

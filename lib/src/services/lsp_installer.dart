import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/models/models.dart';
import 'package:lumide_php/src/services/services.dart';
import 'package:lumide_php/src/utils/utils.dart';
import 'package:path/path.dart' as p;

/// Installs servers only in response to an explicit user command.
class PhpLspInstaller {
  PhpLspInstaller(
      this._context, this._resolver, this._logger, this._phpService);

  final LumideContext _context;
  final PhpLspResolver _resolver;
  final LogService _logger;
  final PhpService? _phpService;

  Future<PhpLspServer?> installIntelephense() async {
    try {
      final existing = await _resolver.resolve(LspServerType.intelephense);
      if (existing != null) return existing;
      await _context.window.showMessage(
        'Installing Intelephense with npm...',
        title: pluginName,
      );
      final result = await _context.shell
          .run('npm', const ['install', '-g', 'intelephense']);
      if (result.exitCode != 0) {
        throw StateError('${result.stderr}\n${result.stdout}'.trim());
      }
      final installed = await _resolver.resolve(LspServerType.intelephense);
      if (installed == null) {
        throw StateError(
            'npm completed, but Intelephense was not found on PATH.');
      }
      return installed;
    } catch (error) {
      await _showError('Intelephense', error);
      return null;
    }
  }

  Future<PhpLspServer?> installPhpactor() async {
    try {
      final existing = await _resolver.resolve(LspServerType.phpactor);
      if (existing != null) return existing;
      if (!(_phpService?.hasPhp ?? false)) {
        throw StateError(
            'PHP 8.2+ is required. Install PHP or configure "$configPhpExecutable" first.');
      }
      await _context.window.showMessage(
          'Downloading Phpactor standalone PHAR...',
          title: pluginName);
      const url =
          'https://github.com/phpactor/phpactor/releases/latest/download/phpactor.phar';
      final storage =
          normalizeFilePath(await _context.workspace.getPluginStorageDir());
      final target = p.join(storage, 'phpactor.phar');
      var downloaded = false;
      try {
        await _context.fs.downloadFile(url, target,
            label: 'Downloading Phpactor Language Server...');
        downloaded = await _context.fs.exists(target);
      } catch (error) {
        _logger.warning('downloadFile failed, falling back to curl: $error');
      }
      if (!downloaded) {
        final result = await _context.shell.run('curl', ['-fLo', target, url]);
        if (result.exitCode != 0) {
          throw StateError('${result.stderr}\n${result.stdout}'.trim());
        }
      }
      final php = _phpService?.phpExecutable ?? 'php';
      if (!await _resolver.verifyExecutable(php, [target, '--version'])) {
        throw StateError(
            'Phpactor downloaded but failed verification. Ensure PHP 8.2+ is installed.');
      }
      return PhpLspServer(
          type: LspServerType.phpactor,
          command: php,
          args: [target, 'language-server']);
    } catch (error) {
      await _showError('Phpactor', error);
      return null;
    }
  }

  Future<void> _showError(String name, Object error) async {
    _logger.error('Failed to install $name', error);
    await _context.window.showMessage('Failed to install $name: $error',
        title: pluginName, type: MessageType.error);
  }
}

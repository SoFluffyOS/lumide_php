/// PHP linting and code formatting service.
library;

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/services/log_service.dart';
import 'package:lumide_php/src/services/php_service.dart';
import 'package:lumide_php/src/utils/utils.dart';
import 'package:path/path.dart' as p;

class PhpFormatterService {
  PhpFormatterService(this._context, this._phpService, this._logger);

  final LumideContext _context;
  final PhpService _phpService;
  final LogService _logger;

  /// Lints a PHP file using `php -l <path>`.
  Future<void> lintActiveFile([Object? args]) async {
    if (!_phpService.hasPhp) {
      await _context.window.showMessage(
        'PHP CLI is not installed or not found on PATH. Configure "php.executablePath" in settings.',
        title: 'PHP Lint',
        type: MessageType.error,
      );
      return;
    }

    final filePath = await _resolveFilePath(args);
    if (filePath == null) {
      await _context.window.showMessage(
        'No PHP file selected to lint.',
        title: 'PHP Lint',
        type: MessageType.warning,
      );
      return;
    }

    if (!filePath.endsWith('.php') && !filePath.endsWith('.phtml')) {
      await _context.window.showMessage(
        'Selected file is not a PHP file.',
        title: 'PHP Lint',
        type: MessageType.warning,
      );
      return;
    }

    try {
      final res = await _context.shell.run(
        _phpService.phpExecutable,
        ['-l', filePath],
      );

      final output = '${res.stdout}\n${res.stderr}'.trim();
      final type = switch (res.exitCode) {
        0 => MessageType.info,
        _ => MessageType.error,
      };

      await _context.window.showMessage(
        output,
        title: 'PHP Lint',
        type: type,
      );
    } catch (e) {
      _logger.error('Failed to lint file', e);
      await _context.window.showMessage(
        'Failed to lint file: $e',
        title: 'PHP Lint',
        type: MessageType.error,
      );
    }
  }

  /// Formats a PHP file using Laravel Pint or PHP-CS-Fixer.
  Future<void> formatActiveFile([Object? args]) async {
    final filePath = await _resolveFilePath(args);
    if (filePath == null) {
      await _context.window.showMessage(
        'No PHP file selected to format.',
        title: 'PHP Formatter',
        type: MessageType.warning,
      );
      return;
    }

    final formatter = await _resolveFormatter();
    if (formatter == null) {
      await _context.window.showMessage(
        'No PHP code formatter (Pint / PHP-CS-Fixer) found.\n'
        'Install Pint: composer require --dev laravel/pint\n'
        'Install PHP-CS-Fixer: composer require --dev friendsofphp/php-cs-fixer',
        title: 'PHP Formatter',
        type: MessageType.warning,
      );
      return;
    }

    final root = await _context.workspace.getRootUri() ?? '';
    final normalizedRoot = root.isNotEmpty ? normalizeFilePath(root) : '';

    try {
      final args = switch (formatter.name) {
        'pint' => [filePath],
        'php-cs-fixer' => ['fix', filePath],
        _ => [filePath],
      };

      final res = await _context.shell.run(
        formatter.executable,
        args,
        workingDirectory: normalizedRoot.isEmpty ? null : normalizedRoot,
      );
      if (res.exitCode == 0) {
        await _context.window.showMessage(
          'Formatted with ${formatter.name}: ${p.basename(filePath)}',
          title: 'PHP Formatter',
          type: MessageType.info,
        );
        return;
      }

      await _context.window.showMessage(
        'Formatting failed:\n${res.stderr}\n${res.stdout}',
        title: 'PHP Formatter',
        type: MessageType.error,
      );
    } catch (e) {
      _logger.error('Formatting execution failed', e);
      await _context.window.showMessage(
        'Formatter failed: $e',
        title: 'PHP Formatter',
        type: MessageType.error,
      );
    }
  }

  Future<({String name, String executable})?> _resolveFormatter() async {
    final root = await _context.workspace.getRootUri() ?? '';

    // Check Pint
    final pintPath = await _phpService.resolveToolExecutable(
      'pint',
      workspaceRoot: root,
    );
    final hasPint = await _canRun(pintPath);
    if (hasPint) {
      return (name: 'pint', executable: pintPath);
    }

    // Check PHP-CS-Fixer
    final csFixerPath = await _phpService.resolveToolExecutable(
      'php-cs-fixer',
      workspaceRoot: root,
    );
    final hasCsFixer = await _canRun(csFixerPath);
    if (hasCsFixer) {
      return (name: 'php-cs-fixer', executable: csFixerPath);
    }

    return null;
  }

  Future<bool> _canRun(String executable) async {
    try {
      final res = await _context.shell.run(executable, const ['--version']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolveFilePath(Object? args) async {
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
    final activeDoc = await _context.editor.getActiveDocumentUri();
    if (activeDoc case final doc? when doc.isNotEmpty) {
      return normalizeFilePath(doc);
    }
    return null;
  }
}

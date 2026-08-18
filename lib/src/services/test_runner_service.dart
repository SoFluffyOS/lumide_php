/// Test runner service for PHPUnit and Pest.
library;

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/services/launch_service.dart';
import 'package:lumide_php/src/services/log_service.dart';
import 'package:lumide_php/src/services/php_service.dart';
import 'package:lumide_php/src/utils/utils.dart';
import 'package:path/path.dart' as p;

class PhpTestRunnerService {
  PhpTestRunnerService(this._context, this._phpService, this._logger);

  final LumideContext _context;
  final PhpService _phpService;
  final LogService _logger;

  PhpLaunchService? launchService;

  /// Runs all test suites in the workspace using Pest or PHPUnit.
  Future<void> runAllTests() async {
    if (launchService case final ls?) {
      await ls.runTestsProcess(all: true);
      return;
    }

    final runner = await resolveTestRunner();
    if (runner == null) {
      await _context.window.showMessage(
        'Neither Pest nor PHPUnit was found in vendor/bin or PATH.\n'
        'Install Pest: composer require --dev pestphp/pest\n'
        'Install PHPUnit: composer require --dev phpunit/phpunit',
        title: 'PHP Tests',
        type: MessageType.warning,
      );
      return;
    }

    await _runInTerminal(runner, const <String>[],
        title: 'PHP Tests ($runner)');
  }

  /// Runs tests for a specified file or active editor document.
  Future<void> runActiveFile([Object? args]) async {
    final filePath = await _resolveFilePath(args);
    if (filePath == null) {
      await _context.window.showMessage(
        'No file selected to run tests for.',
        title: 'PHP Tests',
        type: MessageType.warning,
      );
      return;
    }

    if (launchService case final ls?) {
      await ls.runTestsProcess(all: false, targetFile: filePath);
      return;
    }

    final runner = await resolveTestRunner();
    if (runner == null) {
      await _context.window.showMessage(
        'No PHP test runner (Pest / PHPUnit) detected.',
        title: 'PHP Tests',
        type: MessageType.warning,
      );
      return;
    }

    await _runInTerminal(
      runner,
      [filePath],
      title: 'PHP Test: ${p.basename(filePath)}',
    );
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

  /// Detects whether Pest or PHPUnit is configured in the project.
  Future<String?> resolveTestRunner() async {
    final root = await _context.workspace.getRootUri() ?? '';

    // Check Pest first
    final pestPath = await _phpService.resolveToolExecutable(
      'pest',
      workspaceRoot: root,
    );
    final hasPest = await _canRun(pestPath);
    if (hasPest) {
      return pestPath;
    }

    // Check PHPUnit
    final phpunitPath = await _phpService.resolveToolExecutable(
      'phpunit',
      workspaceRoot: root,
    );
    final hasPhpunit = await _canRun(phpunitPath);
    if (hasPhpunit) {
      return phpunitPath;
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

  Future<void> _runInTerminal(
    String executable,
    List<String> args, {
    required String title,
  }) async {
    try {
      final terminal = await _context.window.createTerminal(
        name: title,
      );
      await terminal.show();

      final fullCommand =
          args.isEmpty ? executable : '$executable ${args.join(' ')}';
      await terminal.sendText(fullCommand);
    } catch (e) {
      _logger.error('Failed to run test terminal', e);
      await _context.window.showMessage(
        'Failed to start test terminal: $e',
        title: 'PHP Tests',
        type: MessageType.error,
      );
    }
  }
}

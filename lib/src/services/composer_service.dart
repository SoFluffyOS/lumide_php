/// Composer dependency manager integration service.
library;

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/models/models.dart';
import 'package:lumide_php/src/services/log_service.dart';
import 'package:lumide_php/src/utils/utils.dart';
import 'package:path/path.dart' as p;

class ComposerService {
  ComposerService(this._context, this._logger);

  final LumideContext _context;
  final LogService _logger;

  String _composerExecutable = 'composer';

  String get composerExecutable => _composerExecutable;

  /// Initializes Composer configuration.
  Future<void> init() async {
    final customPath = await _context.workspace.getConfiguration(
      configComposerPath,
    );
    if (customPath case final String path when path.trim().isNotEmpty) {
      _composerExecutable = path.trim();
    }
  }

  /// Runs `composer install` in an integrated terminal.
  Future<void> install() async {
    await _runComposerInTerminal(const ['install'], title: 'Composer Install');
  }

  /// Runs `composer update` in an integrated terminal.
  Future<void> update() async {
    await _runComposerInTerminal(const ['update'], title: 'Composer Update');
  }

  /// Runs `composer dump-autoload` in an integrated terminal.
  Future<void> dumpAutoload() async {
    await _runComposerInTerminal(
      const ['dump-autoload', '-o'],
      title: 'Composer Dump Autoload',
    );
  }

  /// Validates `composer.json`.
  Future<void> validate() async {
    final root = await _context.workspace.getRootUri() ?? '';
    final normalizedRoot = root.isNotEmpty ? normalizeFilePath(root) : '';
    try {
      final res = await _context.shell.run(
        _composerExecutable,
        const ['validate'],
        workingDirectory: normalizedRoot.isEmpty ? null : normalizedRoot,
      );

      final message = '${res.stdout}\n${res.stderr}'.trim();
      final type = switch (res.exitCode) {
        0 => MessageType.info,
        _ => MessageType.error,
      };

      final displayMessage = switch (message.isEmpty) {
        true => 'composer.json is valid.',
        false => message,
      };

      await _context.window.showMessage(
        displayMessage,
        title: 'Composer Validate',
        type: type,
      );
    } catch (e) {
      await _context.window.showMessage(
        'Failed to run composer validate: $e',
        title: 'Composer Validate',
        type: MessageType.error,
      );
    }
  }

  /// Prompts for package name and runs `composer require <package>`.
  Future<void> requirePackage() async {
    final packageName = await _context.window.showInputBox(
      prompt:
          'Enter PHP package name to require (e.g. symfony/yaml or pestphp/pest:^2.0)',
      placeHolder: 'vendor/package',
      title: 'Composer Require',
    );

    if (packageName == null || packageName.trim().isEmpty) {
      return;
    }

    final trimmed = packageName.trim();
    await _runComposerInTerminal(
      ['require', trimmed],
      title: 'Composer Require $trimmed',
    );
  }

  /// Prompts the user with available Composer scripts from composer.json and runs the chosen one.
  Future<void> runScript([Object? args]) async {
    if (args case final String s when s.trim().isNotEmpty) {
      await _runComposerInTerminal(
        ['run-script', s.trim()],
        title: 'Composer: ${s.trim()}',
      );
      return;
    }

    final manifest = await getManifest();
    if (manifest == null || manifest.scripts.isEmpty) {
      await _context.window.showMessage(
        'No custom scripts defined in composer.json',
        title: 'Composer Scripts',
        type: MessageType.warning,
      );
      return;
    }

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

    final items = <QuickPickItem>[
      const QuickPickItem(
        label: 'Composer scripts',
        enabled: false,
      ),
      const QuickPickItem(
        label: '',
        isSeparator: true,
      ),
      ...manifest.scripts.keys.map((name) {
        final detail = switch (manifest.scripts[name]) {
          final List list => list.join(' && '),
          final v => v.toString(),
        };
        return QuickPickItem(
          label: name,
          tooltip: switch (detail.isNotEmpty) {
            true => detail,
            false => 'composer run-script $name',
          },
          icon: iconTerminal,
          payload: name,
        );
      }),
    ];

    final picked = await _context.window.showQuickPick(
      items,
      placeholder: 'Select Composer Script to run',
      position: position,
    );

    if (picked == null) {
      return;
    }

    final scriptName = switch (picked.payload) {
      final String s => s,
      _ => picked.label,
    };

    await _runComposerInTerminal(
      ['run-script', scriptName],
      title: 'Composer: $scriptName',
    );
  }

  /// Loads and parses composer.json from workspace root if it exists.
  Future<ComposerManifest?> getManifest() async {
    final root = await _context.workspace.getRootUri() ?? '';
    final normalizedRoot = root.isNotEmpty ? normalizeFilePath(root) : '';
    if (normalizedRoot.isEmpty) {
      return null;
    }

    final manifestPath = p.join(normalizedRoot, 'composer.json');
    final exists = await _context.fs.exists(manifestPath);
    if (!exists) {
      return null;
    }

    try {
      final content = await _context.fs.readString(manifestPath);
      return ComposerManifest.parse(content);
    } catch (e) {
      _logger.error('Failed to parse composer.json', e);
      return null;
    }
  }

  Future<void> _runComposerInTerminal(
    List<String> args, {
    required String title,
  }) async {
    try {
      final terminal = await _context.window.createTerminal(
        name: title,
      );
      await terminal.show();

      final fullCommand = args.isEmpty
          ? _composerExecutable
          : '$_composerExecutable ${args.join(' ')}';
      await terminal.sendText(fullCommand);
    } catch (e) {
      _logger.error('Failed to launch terminal for $title', e);
      await _context.window.showMessage(
        'Failed to start terminal for $title: $e',
        title: 'Composer',
        type: MessageType.error,
      );
    }
  }
}

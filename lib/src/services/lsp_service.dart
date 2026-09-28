/// Discovers PHP servers; Lumide owns their runtime state and controls.
library;

import 'dart:async';
import 'dart:convert';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/models/models.dart';
import 'package:lumide_php/src/services/services.dart';

class PhpLspService {
  PhpLspService(this._context, this._logger, [PhpService? phpService])
      : _resolver = PhpLspResolver(_context, phpService) {
    _installer = PhpLspInstaller(_context, _resolver, _logger, phpService);
  }

  final LumideContext _context;
  final LogService _logger;
  final PhpLspResolver _resolver;
  late final PhpLspInstaller _installer;
  final _registered = <LspServerType, PhpLspServer>{};
  Future<void> _registrationQueue = Future.value();
  Future<bool>? _discovery;

  List<PhpLspServer> get registeredServers =>
      List.unmodifiable(_registered.values);
  String get registeredSummary => switch (_registered.isEmpty) {
        true => 'No PHP servers registered',
        false =>
          'Registered: ${_registered.values.map((server) => server.type.label).join(', ')}',
      };

  Future<bool> init() =>
      _discovery ??= _discover().whenComplete(() => _discovery = null);

  Future<bool> _discover() async {
    final configured =
        await _context.workspace.getConfiguration(configLspServer);
    final preferred = LspServerType.fromString(configured as String?);
    final order = <LspServerType>{
      if (preferred != LspServerType.auto) preferred,
      LspServerType.intelephense,
      LspServerType.phpactor,
      LspServerType.phpLanguageServer,
      LspServerType.custom,
    };
    // Resolve independently, then register in a deterministic preference order.
    final servers = await Future.wait(order.map((type) async {
      try {
        return await _resolver.resolve(type);
      } catch (error) {
        _logger.warning('Could not discover ${type.label}: $error');
        return null;
      }
    }));
    for (final server in servers) {
      if (server == null) continue;
      // Keep the built-in provider ID when a custom path aliases a known server.
      if (server.type == LspServerType.custom &&
          servers.any((other) =>
              other != null &&
              other.type != LspServerType.custom &&
              _executionKey(other) == _executionKey(server))) {
        continue;
      }
      try {
        await _register(server);
      } catch (error) {
        _logger.error('Could not register ${server.type.label}', error);
      }
    }
    if (_registered.isNotEmpty) return true;
    await _context.window.showMessage(
      'No PHP language servers could be registered. Install Intelephense or Phpactor from the PHP Tools menu, then use Discover Language Servers.',
      title: pluginName,
      type: MessageType.warning,
    );
    return false;
  }

  String _executionKey(PhpLspServer server) =>
      jsonEncode([server.command, server.args]);

  Future<void> _register(PhpLspServer server) {
    final registration = _registrationQueue.then((_) async {
      if (_registered.containsKey(server.type)) return;
      final execution = _executionKey(server);
      if (_registered.values
          .any((other) => _executionKey(other) == execution)) {
        return;
      }
      final options = switch (server.type) {
        LspServerType.intelephense => await _intelephenseOptions(),
        _ => null,
      };
      await _context.languages.registerLanguageServer(
        id: server.providerId,
        languageId: phpLanguageId,
        displayName: server.type.label,
        fileExtensions: phpFileExtensions,
        extensionLanguageMap: {
          for (final extension in phpFileExtensions) extension: phpLanguageId
        },
        command: server.command,
        args: server.args,
        initializationOptions: options,
      );
      _registered[server.type] = server;
      _logger.info('Registered ${server.type.label} (${server.command})');
    });
    _registrationQueue =
        registration.then<void>((_) {}, onError: (Object _) {});
    return registration;
  }

  Future<Map<String, dynamic>?> _intelephenseOptions() async {
    final licence =
        await _context.workspace.getConfiguration(configIntelephenseLicence);
    if (licence case final String key when key.trim().isNotEmpty) {
      return {'licenceKey': key.trim()};
    }
    return null;
  }

  Future<void> refreshServers() async {
    await init();
    if (_registered.isNotEmpty) await showStatus();
  }

  Future<void> showStatus() async {
    final details = _registered.values
        .map((server) => '${server.type.label}: ${server.command}')
        .join('\n');
    await _context.window.showMessage(
      '$registeredSummary\n$details\n\n'
      'Open Lumide’s runtime controls → LSP & Agents to Start, Stop for this session, Disable in this workspace, Enable, or Restart each server.\n\n'
      'Registered servers may be stopped or disabled. Reload the PHP plugin after changing the preferred server, custom path, or licence key.',
      title: 'PHP Language Servers',
    );
  }

  Future<void> installIntelephense() async =>
      _registerInstalled(await _installer.installIntelephense());
  Future<void> installPhpactor() async =>
      _registerInstalled(await _installer.installPhpactor());

  Future<void> _registerInstalled(PhpLspServer? server) async {
    if (server == null) return;
    try {
      await _register(server);
      await showStatus();
    } catch (error) {
      _logger.error('Could not register installed ${server.type.label}', error);
      await _context.window.showMessage(
          'Could not register ${server.type.label}: $error',
          title: pluginName,
          type: MessageType.error);
    }
  }
}

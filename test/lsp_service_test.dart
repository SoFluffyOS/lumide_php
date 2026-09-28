import 'dart:async';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_php/lumide_php.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late RpcSession plugin;
  late RpcSession host;
  late PhpLspService service;
  late Map<String, Object?> settings;
  late Map<String, String> executables;
  late List<Map<dynamic, dynamic>> registrations;
  late List<Map<dynamic, dynamic>> commands;
  late List<String> messages;
  late Set<String> failingProviders;
  var installFails = false;

  setUp(() {
    final channels = StreamChannelController<String>(sync: true);
    plugin = RpcSession(channels.local);
    host = RpcSession(channels.foreign);
    final pluginListening = plugin.listen();
    final hostListening = host.listen();
    addTearDown(() async {
      await Future.wait([plugin.close(), host.close()]);
      await Future.wait([pluginListening, hostListening]);
    });
    settings = {};
    executables = {};
    registrations = [];
    commands = [];
    messages = [];
    failingProviders = {};
    installFails = false;
    host.registerMethod(PluginMethods.workspaceGetConfiguration,
        (params) => settings[(params.value as Map)['section']]);
    host.registerMethod(
        PluginMethods.workspaceGetPluginStorageDir, (_) => '/storage/php');
    host.registerMethod(PluginMethods.fsExists, (_) => false);
    host.registerMethod(PluginMethods.windowShowMessage, (params) {
      messages.add((params.value as Map)['message'] as String);
      return null;
    });
    host.registerMethod(PluginMethods.shellRun, (params) {
      final request = params.value as Map;
      commands.add(request);
      final command = request['command'];
      final args = (request['arguments'] as List).cast<String>();
      if (command == 'which' || command == 'where') {
        final path = executables[args.single] ??
            switch (executables.values.contains(args.single)) {
              true => args.single,
              false => null,
            };
        return {
          'exitCode': switch (path) { null => 1, _ => 0 },
          'stdout': path ?? '',
          'stderr': ''
        };
      }
      if (command == 'npm') {
        expect(args, ['install', '-g', 'intelephense']);
        if (installFails) {
          return {'exitCode': 1, 'stdout': '', 'stderr': 'installation failed'};
        }
        executables['intelephense'] = '/bin/intelephense';
        return {'exitCode': 0, 'stdout': '', 'stderr': ''};
      }
      throw StateError('Unexpected process: $command $args');
    });
    host.registerMethod(PluginMethods.languagesRegisterServer, (params) {
      final registration = params.value as Map;
      if (failingProviders.contains(registration['id'])) {
        throw StateError('registration failed');
      }
      registrations.add(registration);
      return null;
    });
    service = PhpLspService(RpcLumideContext(plugin), LogService((_) {}));
  });

  test(
      'registers all installed servers, with PHP IDs and scoped licence options',
      () async {
    executables.addAll({
      'intelephense': '/bin/intelephense',
      'phpactor': '/bin/phpactor',
      'php-language-server.php': '/bin/php-language-server.php',
      '/custom/php-lsp': '/custom/php-lsp'
    });
    settings[configLspServer] = 'phpactor';
    settings[configLspPath] = '/custom/php-lsp';
    settings[configIntelephenseLicence] = ' licence ';
    expect(await service.init(), isTrue);
    expect(registrations.map((entry) => entry['id']), [
      lspProviderIdPhpactor,
      lspProviderIdIntelephense,
      lspProviderIdPhpLanguageServer,
      lspProviderIdCustom
    ]);
    for (final registration in registrations) {
      expect(registration['extensionLanguageMap'],
          {for (final extension in phpFileExtensions) extension: 'php'});
      if (registration['id'] == lspProviderIdIntelephense) {
        expect(
            registration['initializationOptions'], {'licenceKey': 'licence'});
        continue;
      }
      expect(registration.containsKey('initializationOptions'), isFalse);
    }
    expect(registrations.first['args'], ['language-server']);
    expect(
        commands
            .every((entry) => ['which', 'where'].contains(entry['command'])),
        isTrue);
    expect(service.registeredSummary,
        contains('Registered: Phpactor, Intelephense'));
  });

  test('refresh is idempotent and adds a newly installed server', () async {
    executables['intelephense'] = '/bin/intelephense';
    await Future.wait([service.init(), service.init()]);
    executables['phpactor'] = '/bin/phpactor';
    await service.refreshServers();
    await service.refreshServers();
    expect(registrations.map((entry) => entry['id']),
        [lspProviderIdIntelephense, lspProviderIdPhpactor]);
    expect(messages.last, contains('stopped or disabled'));
  });

  test('custom alias retains the known server ID without double registration',
      () async {
    executables['intelephense'] = '/bin/intelephense';
    settings[configLspServer] = 'custom';
    settings[configLspPath] = '/bin/intelephense';
    await service.init();
    expect(registrations.single['id'], lspProviderIdIntelephense);
  });

  test('one failed registration does not block others and can be retried',
      () async {
    executables.addAll(
        {'intelephense': '/bin/intelephense', 'phpactor': '/bin/phpactor'});
    failingProviders.add(lspProviderIdIntelephense);
    expect(await service.init(), isTrue);
    expect(registrations.single['id'], lspProviderIdPhpactor);
    failingProviders.clear();
    await service.init();
    expect(registrations.map((entry) => entry['id']),
        [lspProviderIdPhpactor, lspProviderIdIntelephense]);
  });

  test('discovery never installs missing servers', () async {
    expect(await service.init(), isFalse);
    expect(registrations, isEmpty);
    expect(messages.single, contains('No PHP language servers'));
    expect(commands.any((entry) => entry['command'] == 'npm'), isFalse);
  });

  test('installation adds Intelephense without replacing Phpactor', () async {
    executables['phpactor'] = '/bin/phpactor';
    await service.init();
    await service.installIntelephense();
    await service.installIntelephense();
    expect(registrations.map((entry) => entry['id']),
        [lspProviderIdPhpactor, lspProviderIdIntelephense]);
    expect(commands.where((entry) => entry['command'] == 'npm'), hasLength(1));
    expect(messages.last, contains('Registered: Phpactor, Intelephense'));
  });

  test('failed installation preserves existing registrations', () async {
    executables['phpactor'] = '/bin/phpactor';
    await service.init();
    installFails = true;
    await service.installIntelephense();
    expect(registrations.single['id'], lspProviderIdPhpactor);
    expect(messages.last, contains('Failed to install Intelephense'));
  });
}

import 'package:lumide_php/src/constants.dart';
import 'package:lumide_php/src/models/models.dart';

/// A discovered executable, independent of Lumide's running/disabled state.
class PhpLspServer {
  const PhpLspServer({
    required this.type,
    required this.command,
    required this.args,
  });

  final LspServerType type;
  final String command;
  final List<String> args;

  String get providerId => switch (type) {
        LspServerType.intelephense => lspProviderIdIntelephense,
        LspServerType.phpactor => lspProviderIdPhpactor,
        LspServerType.phpLanguageServer => lspProviderIdPhpLanguageServer,
        LspServerType.custom => lspProviderIdCustom,
        LspServerType.auto => throw StateError('Auto is not a server.'),
      };
}

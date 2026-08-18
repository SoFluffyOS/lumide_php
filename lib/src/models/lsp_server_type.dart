/// Supported PHP LSP server types.
library;

/// Represents the supported PHP Language Server implementations.
enum LspServerType {
  auto('auto', 'Auto-detect'),
  intelephense('intelephense', 'Intelephense'),
  phpactor('phpactor', 'Phpactor'),
  phpLanguageServer('php-language-server', 'PHP Language Server'),
  custom('custom', 'Custom');

  const LspServerType(this.id, this.label);

  final String id;
  final String label;

  /// Returns the identifier string for JSON serialization.
  String toJson() => id;

  /// Parses an identifier into an [LspServerType], defaulting to [auto].
  static LspServerType fromString(String? raw) {
    if (raw == null) {
      return LspServerType.auto;
    }
    return switch (raw.toLowerCase().trim()) {
      'intelephense' => LspServerType.intelephense,
      'phpactor' => LspServerType.phpactor,
      'php-language-server' ||
      'phplanguageserver' =>
        LspServerType.phpLanguageServer,
      'custom' => LspServerType.custom,
      _ => LspServerType.auto,
    };
  }

  /// Returns the default binary name/command for this server type.
  String get defaultCommand {
    return switch (this) {
      LspServerType.intelephense || LspServerType.auto => 'intelephense',
      LspServerType.phpactor => 'phpactor',
      LspServerType.phpLanguageServer => 'php-language-server',
      LspServerType.custom => '',
    };
  }

  /// Returns the CLI arguments needed for STDIO communication.
  List<String> get defaultArgs {
    return switch (this) {
      LspServerType.intelephense || LspServerType.auto => const ['--stdio'],
      LspServerType.phpactor => const ['language-server'],
      LspServerType.phpLanguageServer => const [],
      LspServerType.custom => const [],
    };
  }
}

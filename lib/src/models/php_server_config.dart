/// Configuration model for the PHP built-in web server.
library;

/// Settings for launching `php -S <host>:<port> -t <docRoot>`.
class PhpServerConfig {
  const PhpServerConfig({
    this.host = '127.0.0.1',
    this.port = 8000,
    this.documentRoot = '',
  });

  final String host;
  final int port;
  final String documentRoot;

  /// URL string representing the running server address.
  String get url => 'http://$host:$port';

  /// Creates a copy with modified values.
  PhpServerConfig copyWith({
    String? host,
    int? port,
    String? documentRoot,
  }) {
    return PhpServerConfig(
      host: switch (host) {
        final h? => h,
        _ => this.host,
      },
      port: switch (port) {
        final p? => p,
        _ => this.port,
      },
      documentRoot: switch (documentRoot) {
        final d? => d,
        _ => this.documentRoot,
      },
    );
  }
}

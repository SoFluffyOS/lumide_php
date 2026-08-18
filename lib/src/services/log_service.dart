/// Logging service for Lumide PHP plugin.
library;

import 'package:lumide_php/src/constants.dart';

typedef LogFunction = void Function(String message);

class LogService {
  const LogService(this._log);

  final LogFunction _log;

  void info(String message) {
    _log('$logPrefix [INFO] $message');
  }

  void warning(String message) {
    _log('$logPrefix [WARN] $message');
  }

  void error(String message, [Object? error]) {
    final suffix = switch (error) {
      final e? => ' ($e)',
      _ => '',
    };
    _log('$logPrefix [ERROR] $message$suffix');
  }
}

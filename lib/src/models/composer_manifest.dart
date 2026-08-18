/// Model representing a parsed composer.json file.
library;

import 'dart:convert';

/// Represents metadata extracted from composer.json.
class ComposerManifest {
  const ComposerManifest({
    this.name,
    this.description,
    this.type,
    this.scripts = const {},
    this.require = const {},
    this.requireDev = const {},
  });

  final String? name;
  final String? description;
  final String? type;
  final Map<String, dynamic> scripts;
  final Map<String, String> require;
  final Map<String, String> requireDev;

  /// Parses composer.json content string into a [ComposerManifest].
  static ComposerManifest? parse(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return null;
      }

      final scriptsMap = <String, dynamic>{};
      if (decoded['scripts'] case final Map rawScripts) {
        for (final entry in rawScripts.entries) {
          if (entry.key case final String key) {
            scriptsMap[key] = entry.value;
          }
        }
      }

      final reqMap = <String, String>{};
      if (decoded['require'] case final Map rawReq) {
        for (final entry in rawReq.entries) {
          if (entry.key case final String key) {
            reqMap[key] = entry.value.toString();
          }
        }
      }

      final reqDevMap = <String, String>{};
      if (decoded['require-dev'] case final Map rawReqDev) {
        for (final entry in rawReqDev.entries) {
          if (entry.key case final String key) {
            reqDevMap[key] = entry.value.toString();
          }
        }
      }

      return ComposerManifest(
        name: decoded['name']?.toString(),
        description: decoded['description']?.toString(),
        type: decoded['type']?.toString(),
        scripts: scriptsMap,
        require: reqMap,
        requireDev: reqDevMap,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns true if this manifest requires the given package.
  bool hasDependency(String packageName) {
    final lower = packageName.toLowerCase();
    final inReq = require.keys.any((k) => k.toLowerCase() == lower);
    if (inReq) {
      return true;
    }
    return requireDev.keys.any((k) => k.toLowerCase() == lower);
  }
}

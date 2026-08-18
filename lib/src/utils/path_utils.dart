/// Path utilities for Lumide PHP plugin.
library;

/// Normalizes a file URI or raw path string to a native filesystem path.
String normalizeFilePath(String raw) {
  if (raw.startsWith('file://')) {
    try {
      return Uri.parse(raw).toFilePath();
    } catch (_) {
      return raw;
    }
  }
  return raw;
}

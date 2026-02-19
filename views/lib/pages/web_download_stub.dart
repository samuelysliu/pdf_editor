import 'dart:typed_data';

/// Stub implementation for non-web platforms.
/// This file is used when dart:html is not available.
void downloadFile(Uint8List data, String filename, [String? mimeType]) {
  // No-op on non-web platforms
  throw UnsupportedError('downloadFile is only supported on web platforms');
}

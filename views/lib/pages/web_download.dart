// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Web implementation: triggers a browser file download.
void downloadFile(Uint8List data, String filename, [String? mimeType]) {
  final effectiveMime = mimeType ?? 'application/octet-stream';
  final blob = html.Blob([data], effectiveMime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

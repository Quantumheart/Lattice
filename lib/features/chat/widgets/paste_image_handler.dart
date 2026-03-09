import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

class ClipboardImageData {
  const ClipboardImageData({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}

Future<bool> clipboardHasImage() async {
  final bytes = await Pasteboard.image;
  return bytes != null && bytes.isNotEmpty;
}

Future<ClipboardImageData?> readClipboardImage() async {
  final bytes = await Pasteboard.image;
  if (bytes == null || bytes.isEmpty) return null;
  return ClipboardImageData(bytes: bytes, mimeType: 'image/png');
}

String generatePasteFilename(String mimeType) {
  final ext = switch (mimeType) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => 'png',
  };
  final now = DateTime.now();
  final stamp = '${now.year}'
      '${_pad(now.month)}'
      '${_pad(now.day)}'
      '_'
      '${_pad(now.hour)}'
      '${_pad(now.minute)}'
      '${_pad(now.second)}';
  return 'paste_$stamp.$ext';
}

String _pad(int n) => n.toString().padLeft(2, '0');

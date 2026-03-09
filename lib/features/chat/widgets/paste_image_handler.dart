import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

class ClipboardImageData {
  const ClipboardImageData({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}

String _detectMimeType(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return 'image/gif';
  }
  if (bytes.length >= 12 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/png';
}

Future<ClipboardImageData?> readClipboardImage() async {
  final bytes = await Pasteboard.image;
  if (bytes == null || bytes.isEmpty) return null;
  return ClipboardImageData(bytes: bytes, mimeType: _detectMimeType(bytes));
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

import 'dart:async';
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

class ClipboardImageData {
  const ClipboardImageData({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}

final _formats = <(SimpleFileFormat, String)>[
  (Formats.png, 'image/png'),
  (Formats.jpeg, 'image/jpeg'),
  (Formats.gif, 'image/gif'),
  (Formats.webp, 'image/webp'),
];

Future<ClipboardImageData?> readClipboardImage() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;

  final reader = await clipboard.read();

  for (final (format, mime) in _formats) {
    if (!reader.canProvide(format)) continue;

    final completer = Completer<Uint8List?>();
    reader.getFile(
      format,
      (file) async {
        final bytes = await file.readAll();
        completer.complete(bytes);
      },
      onError: (_) => completer.complete(null),
    );

    final bytes = await completer.future;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipboardImageData(bytes: bytes, mimeType: mime);
    }
  }

  return null;
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

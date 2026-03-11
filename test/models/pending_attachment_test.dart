import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/core/models/pending_attachment.dart';

void main() {
  group('PendingAttachment', () {
    test('constructor stores all fields', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final attachment = PendingAttachment(bytes: bytes, name: 'test.png', isImage: true);
      expect(attachment.bytes, bytes);
      expect(attachment.name, 'test.png');
      expect(attachment.isImage, isTrue);
    });

    test('fromBytes detects image files', () {
      final bytes = Uint8List.fromList([0]);
      final attachment = PendingAttachment.fromBytes(bytes: bytes, name: 'photo.jpg');
      expect(attachment.isImage, isTrue);
      expect(attachment.name, 'photo.jpg');
    });

    test('fromBytes detects non-image files', () {
      final bytes = Uint8List.fromList([0]);
      final attachment = PendingAttachment.fromBytes(bytes: bytes, name: 'doc.pdf');
      expect(attachment.isImage, isFalse);
    });
  });

  group('isImageFile', () {
    test('recognizes all supported image extensions', () {
      for (final ext in ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp']) {
        expect(PendingAttachment.isImageFile('file$ext'), isTrue, reason: ext);
      }
    });

    test('is case-insensitive', () {
      expect(PendingAttachment.isImageFile('PHOTO.PNG'), isTrue);
      expect(PendingAttachment.isImageFile('Image.JPG'), isTrue);
      expect(PendingAttachment.isImageFile('pic.WebP'), isTrue);
    });

    test('rejects non-image extensions', () {
      expect(PendingAttachment.isImageFile('file.pdf'), isFalse);
      expect(PendingAttachment.isImageFile('file.txt'), isFalse);
      expect(PendingAttachment.isImageFile('file.mp4'), isFalse);
      expect(PendingAttachment.isImageFile('file.svg'), isFalse);
    });
  });
}

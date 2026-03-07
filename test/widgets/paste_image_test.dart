import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/core/models/pending_attachment.dart';
import 'package:lattice/features/chat/widgets/paste_image_handler.dart';

void main() {
  group('generatePasteFilename', () {
    test('generates PNG filename', () {
      final name = generatePasteFilename('image/png');
      expect(name, endsWith('.png'));
      expect(name, startsWith('paste_'));
    });

    test('generates JPG filename for JPEG mime', () {
      final name = generatePasteFilename('image/jpeg');
      expect(name, endsWith('.jpg'));
    });

    test('generates GIF filename', () {
      final name = generatePasteFilename('image/gif');
      expect(name, endsWith('.gif'));
    });

    test('generates WebP filename', () {
      final name = generatePasteFilename('image/webp');
      expect(name, endsWith('.webp'));
    });

    test('defaults to PNG for unknown mime', () {
      final name = generatePasteFilename('image/tiff');
      expect(name, endsWith('.png'));
    });

    test('contains timestamp pattern', () {
      final name = generatePasteFilename('image/png');
      final pattern = RegExp(r'^paste_\d{8}_\d{6}\.png$');
      expect(pattern.hasMatch(name), isTrue);
    });
  });

  group('PendingAttachment', () {
    test('isImageFile returns true for image extensions', () {
      expect(PendingAttachment.isImageFile('photo.png'), isTrue);
      expect(PendingAttachment.isImageFile('photo.JPG'), isTrue);
      expect(PendingAttachment.isImageFile('photo.jpeg'), isTrue);
      expect(PendingAttachment.isImageFile('photo.gif'), isTrue);
      expect(PendingAttachment.isImageFile('photo.webp'), isTrue);
      expect(PendingAttachment.isImageFile('photo.bmp'), isTrue);
    });

    test('isImageFile returns false for non-image extensions', () {
      expect(PendingAttachment.isImageFile('doc.pdf'), isFalse);
      expect(PendingAttachment.isImageFile('file.txt'), isFalse);
      expect(PendingAttachment.isImageFile('archive.zip'), isFalse);
    });

    test('fromBytes sets isImage correctly', () {
      final bytes = Uint8List(0);
      final image = PendingAttachment.fromBytes(bytes: bytes, name: 'photo.png');
      expect(image.isImage, isTrue);

      final file = PendingAttachment.fromBytes(bytes: bytes, name: 'doc.pdf');
      expect(file.isImage, isFalse);
    });
  });
}

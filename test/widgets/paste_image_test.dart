import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/features/chat/widgets/paste_confirm_dialog.dart';
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

  group('confirmPastedImage', () {
    final fakeImage = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG header
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
      0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
      0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

    testWidgets('returns null on cancel', (tester) async {
      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await confirmPastedImage(
                    context,
                    fakeImage,
                    'paste_test.png',
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Send pasted image?'), findsOneWidget);
      expect(find.text('paste_test.png'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('returns filename on send', (tester) async {
      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await confirmPastedImage(
                    context,
                    fakeImage,
                    'paste_test.png',
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(result, 'paste_test.png');
    });

    testWidgets('returns edited filename on send', (tester) async {
      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await confirmPastedImage(
                    context,
                    fakeImage,
                    'paste_test.png',
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'screenshot.png');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(result, 'screenshot.png');
    });
  });
}

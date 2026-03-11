import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/core/utils/emoji_spans.dart';

void main() {
  const style = TextStyle(fontSize: 14);

  group('buildEmojiSpans', () {
    test('plain text returns single span without emoji font fallback', () {
      final spans = buildEmojiSpans('hello world', style);
      expect(spans.length, 1);
      expect(spans.first.text, 'hello world');
      expect(spans.first.style?.fontFamilyFallback, isNull);
    });

    test('emoji-only text returns single span with emoji font fallback', () {
      final spans = buildEmojiSpans('😀', style);
      expect(spans.length, 1);
      expect(spans.first.style?.fontFamilyFallback, emojiFontFallback);
    });

    test('mixed text splits into text and emoji spans', () {
      final spans = buildEmojiSpans('hello 😀 world', style);
      expect(spans.length, 3);
      expect(spans[0].text, 'hello ');
      expect(spans[0].style?.fontFamilyFallback, isNull);
      expect(spans[1].style?.fontFamilyFallback, emojiFontFallback);
      expect(spans[2].text, ' world');
      expect(spans[2].style?.fontFamilyFallback, isNull);
    });

    test('multiple emojis in sequence', () {
      final spans = buildEmojiSpans('😀😎', style);
      expect(spans.length, greaterThanOrEqualTo(1));
      for (final span in spans) {
        expect(span.style?.fontFamilyFallback, emojiFontFallback);
      }
    });

    test('null style is handled', () {
      final spans = buildEmojiSpans('hello 😀', null);
      expect(spans.length, 2);
      expect(spans[0].text, 'hello ');
      expect(spans[0].style, isNull);
    });

    test('empty string returns single span', () {
      final spans = buildEmojiSpans('', style);
      expect(spans.length, 1);
      expect(spans.first.text, '');
    });

    test('emoji at start of text', () {
      final spans = buildEmojiSpans('😀hello', style);
      expect(spans.length, 2);
      expect(spans[0].style?.fontFamilyFallback, emojiFontFallback);
      expect(spans[1].text, 'hello');
    });

    test('emoji at end of text', () {
      final spans = buildEmojiSpans('hello😀', style);
      expect(spans.length, 2);
      expect(spans[0].text, 'hello');
      expect(spans[1].style?.fontFamilyFallback, emojiFontFallback);
    });
  });

  group('emojiFontFallback', () {
    test('contains expected font families', () {
      expect(emojiFontFallback, contains('Noto Color Emoji'));
      expect(emojiFontFallback, contains('Apple Color Emoji'));
      expect(emojiFontFallback, contains('Segoe UI Emoji'));
    });
  });
}

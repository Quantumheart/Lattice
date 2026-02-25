import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/utils/text_highlight.dart';

void main() {
  group('highlightSpans', () {
    test('returns single non-match span when query is empty', () {
      final spans = highlightSpans('Hello world', '');
      expect(spans, hasLength(1));
      expect(spans[0].text, 'Hello world');
      expect(spans[0].isMatch, isFalse);
    });

    test('returns single non-match span when query not found', () {
      final spans = highlightSpans('Hello world', 'xyz');
      expect(spans, hasLength(1));
      expect(spans[0].text, 'Hello world');
      expect(spans[0].isMatch, isFalse);
    });

    test('highlights single match at start', () {
      final spans = highlightSpans('Hello world', 'Hello');
      expect(spans, hasLength(2));
      expect(spans[0].text, 'Hello');
      expect(spans[0].isMatch, isTrue);
      expect(spans[1].text, ' world');
      expect(spans[1].isMatch, isFalse);
    });

    test('highlights single match at end', () {
      final spans = highlightSpans('Hello world', 'world');
      expect(spans, hasLength(2));
      expect(spans[0].text, 'Hello ');
      expect(spans[0].isMatch, isFalse);
      expect(spans[1].text, 'world');
      expect(spans[1].isMatch, isTrue);
    });

    test('highlights single match in middle', () {
      final spans = highlightSpans('Hello big world', 'big');
      expect(spans, hasLength(3));
      expect(spans[0].text, 'Hello ');
      expect(spans[0].isMatch, isFalse);
      expect(spans[1].text, 'big');
      expect(spans[1].isMatch, isTrue);
      expect(spans[2].text, ' world');
      expect(spans[2].isMatch, isFalse);
    });

    test('highlights multiple occurrences', () {
      final spans = highlightSpans('abcabc', 'abc');
      expect(spans, hasLength(2));
      expect(spans[0].text, 'abc');
      expect(spans[0].isMatch, isTrue);
      expect(spans[1].text, 'abc');
      expect(spans[1].isMatch, isTrue);
    });

    test('is case-insensitive', () {
      final spans = highlightSpans('Hello HELLO hello', 'hello');
      expect(spans.where((s) => s.isMatch).length, 3);
    });

    test('handles empty text', () {
      final spans = highlightSpans('', 'query');
      expect(spans, isEmpty);
    });

    test('handles query that matches entire text', () {
      final spans = highlightSpans('abc', 'abc');
      expect(spans, hasLength(1));
      expect(spans[0].text, 'abc');
      expect(spans[0].isMatch, isTrue);
    });
  });
}

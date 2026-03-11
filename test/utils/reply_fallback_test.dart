import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/core/utils/reply_fallback.dart';

void main() {
  group('stripReplyFallback', () {
    test('returns body unchanged when no fallback present', () {
      expect(stripReplyFallback('hello world'), 'hello world');
    });

    test('strips single-line fallback', () {
      expect(stripReplyFallback('> quoted\n\nreply'), 'reply');
    });

    test('strips multi-line fallback', () {
      expect(stripReplyFallback('> line 1\n> line 2\n\nreply text'), 'reply text');
    });

    test('strips fallback with bare > line', () {
      expect(stripReplyFallback('> quoted\n>\n\nreply'), 'reply');
    });

    test('strips blank line separator after fallback', () {
      expect(stripReplyFallback('> quoted\n\nmessage'), 'message');
    });

    test('preserves multiline reply content', () {
      expect(
        stripReplyFallback('> quoted\n\nline 1\nline 2'),
        'line 1\nline 2',
      );
    });

    test('empty body returns empty string', () {
      expect(stripReplyFallback(''), '');
    });

    test('only fallback content returns empty string', () {
      expect(stripReplyFallback('> quoted\n'), '');
    });
  });
}

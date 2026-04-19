import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kohera/features/chat/widgets/message_bubble_body.dart';
import 'package:kohera/features/chat/widgets/message_bubble_content.dart';
import 'package:kohera/features/chat/widgets/message_bubble_link_preview.dart';
import 'package:kohera/features/chat/widgets/message_bubble_skin.dart';

void main() {
  group('escapeHtml', () {
    test('escapes all HTML-significant characters', () {
      expect(
        escapeHtml('<script>alert("x")</script>'),
        '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;',
      );
    });

    test('escapes ampersand first to avoid double-encoding', () {
      expect(escapeHtml('a & b < c'), 'a &amp; b &lt; c');
    });

    test('escapes single quotes', () {
      expect(escapeHtml("it's"), 'it&#39;s');
    });

    test('passes plain text through unchanged', () {
      expect(escapeHtml('hello world'), 'hello world');
    });

    test('handles empty string', () {
      expect(escapeHtml(''), '');
    });
  });

  group('redactionLabel', () {
    test('isMe returns "You deleted this message"', () {
      expect(
        redactionLabel(isMe: true, senderId: '@me:x'),
        'You deleted this message',
      );
    });

    test('no redactor returns generic "This message was deleted"', () {
      expect(
        redactionLabel(isMe: false, senderId: '@alice:x'),
        'This message was deleted',
      );
    });

    test('self-redact returns generic "This message was deleted"', () {
      expect(
        redactionLabel(
          isMe: false,
          senderId: '@alice:x',
          redactor: '@alice:x',
        ),
        'This message was deleted',
      );
    });

    test('moderator redact uses display name', () {
      expect(
        redactionLabel(
          isMe: false,
          senderId: '@alice:x',
          redactor: '@bob:x',
          redactorDisplayName: 'Bob',
        ),
        'Deleted by Bob',
      );
    });

    test('moderator redact falls back to user id when name missing', () {
      expect(
        redactionLabel(
          isMe: false,
          senderId: '@alice:x',
          redactor: '@bob:x',
        ),
        'Deleted by @bob:x',
      );
    });

    test('isMe overrides redactor identity', () {
      expect(
        redactionLabel(
          isMe: true,
          senderId: '@me:x',
          redactor: '@mod:x',
          redactorDisplayName: 'Mod',
        ),
        'You deleted this message',
      );
    });
  });

  group('extractFirstPreviewUrl', () {
    test('returns null for empty body', () {
      expect(extractFirstPreviewUrl(''), null);
    });

    test('returns null when no URLs present', () {
      expect(extractFirstPreviewUrl('just plain text here'), null);
    });

    test('returns first http URL', () {
      expect(
        extractFirstPreviewUrl('see https://example.com for details'),
        'https://example.com',
      );
    });

    test('skips matrix.to links', () {
      expect(
        extractFirstPreviewUrl(
            'look at https://matrix.to/#/@bob:x and https://example.com',),
        'https://example.com',
      );
    });

    test('returns null when only matrix.to links present', () {
      expect(
        extractFirstPreviewUrl('https://matrix.to/#/!room:server'),
        null,
      );
    });

    test('returns the first non-matrix URL from multiple', () {
      expect(
        extractFirstPreviewUrl('https://foo.com or https://bar.com'),
        'https://foo.com',
      );
    });
  });

  group('isDirectImageUrl', () {
    test('true for .png', () {
      expect(isDirectImageUrl('https://example.com/pic.png'), true);
    });

    test('true for .jpg / .jpeg', () {
      expect(isDirectImageUrl('https://example.com/pic.jpg'), true);
      expect(isDirectImageUrl('https://example.com/pic.jpeg'), true);
    });

    test('true for .gif', () {
      expect(isDirectImageUrl('https://example.com/pic.gif'), true);
    });

    test('true for .webp', () {
      expect(isDirectImageUrl('https://example.com/pic.webp'), true);
    });

    test('case-insensitive extension match', () {
      expect(isDirectImageUrl('https://example.com/pic.PNG'), true);
      expect(isDirectImageUrl('https://example.com/pic.JPG'), true);
    });

    test('false for non-image paths', () {
      expect(isDirectImageUrl('https://example.com/page.html'), false);
      expect(isDirectImageUrl('https://example.com/'), false);
      expect(isDirectImageUrl('https://example.com'), false);
    });

    test('false for malformed URL', () {
      expect(isDirectImageUrl('not a url'), false);
    });
  });

  group('bubbleRadii', () {
    const radius = 16.0;

    test('isMe && isFirst: tail bottom-right', () {
      final r = bubbleRadii(isMe: true, isFirst: true, radius: radius);
      expect(r.topLeft, const Radius.circular(radius));
      expect(r.topRight, const Radius.circular(radius));
      expect(r.bottomLeft, const Radius.circular(radius));
      expect(r.bottomRight, const Radius.circular(4));
    });

    test('isMe && !isFirst: all full', () {
      final r = bubbleRadii(isMe: true, isFirst: false, radius: radius);
      expect(r.bottomLeft, const Radius.circular(radius));
      expect(r.bottomRight, const Radius.circular(radius));
    });

    test('!isMe && isFirst: tail bottom-left', () {
      final r = bubbleRadii(isMe: false, isFirst: true, radius: radius);
      expect(r.bottomLeft, const Radius.circular(4));
      expect(r.bottomRight, const Radius.circular(radius));
    });

    test('!isMe && !isFirst: all full', () {
      final r = bubbleRadii(isMe: false, isFirst: false, radius: radius);
      expect(r.bottomLeft, const Radius.circular(radius));
      expect(r.bottomRight, const Radius.circular(radius));
    });
  });

  group('extractReplyEventId', () {
    test('returns null when no m.relates_to', () {
      expect(extractReplyEventId(<String, Object?>{'body': 'hi'}), null);
    });

    test('returns null when m.in_reply_to missing', () {
      expect(
        extractReplyEventId(<String, Object?>{
          'm.relates_to': <String, Object?>{'rel_type': 'm.annotation'},
        }),
        null,
      );
    });

    test('returns event_id when present', () {
      expect(
        extractReplyEventId(<String, Object?>{
          'm.relates_to': <String, Object?>{
            'm.in_reply_to': <String, Object?>{'event_id': r'$evt:x'},
          },
        }),
        r'$evt:x',
      );
    });

    test('returns null when event_id is missing from m.in_reply_to', () {
      expect(
        extractReplyEventId(<String, Object?>{
          'm.relates_to': <String, Object?>{
            'm.in_reply_to': <String, Object?>{},
          },
        }),
        null,
      );
    });

    test('returns null when event_id is wrong type', () {
      expect(
        extractReplyEventId(<String, Object?>{
          'm.relates_to': <String, Object?>{
            'm.in_reply_to': <String, Object?>{'event_id': 42},
          },
        }),
        null,
      );
    });
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/widgets/chat/linkable_text.dart';

/// Extracts all [TextSpan] leaves from the [RichText] inside [LinkableText].
///
/// `Text.rich(TextSpan(children: ...))` creates a RichText whose root TextSpan
/// wraps the provided TextSpan, so the actual spans are at root → child[0] → children.
List<TextSpan> _extractSpans(WidgetTester tester) {
  final richText = tester.widget<RichText>(find.byType(RichText).first);
  final root = richText.text as TextSpan;
  // Text.rich nests our TextSpan inside the root as a single child.
  final inner = root.children?.first as TextSpan?;
  if (inner == null) return [root];
  if (inner.children == null || inner.children!.isEmpty) return [inner];
  return inner.children!.cast<TextSpan>();
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('LinkableText', () {
    testWidgets('plain text with no URLs renders as-is', (tester) async {
      await tester.pumpWidget(_wrap(
        const LinkableText(
          text: 'Hello world, no links here',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      // Should render as a single Text widget, not Text.rich with children.
      expect(find.text('Hello world, no links here'), findsOneWidget);
    });

    testWidgets('text with one URL renders a tappable link span',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const LinkableText(
          text: 'Visit https://example.com for info',
          style: TextStyle(fontSize: 14, color: Colors.black),
          isMe: false,
        ),
      ));

      final spans = _extractSpans(tester);
      expect(spans.length, 3);
      expect(spans[0].text, 'Visit ');
      expect(spans[1].text, 'https://example.com');
      expect(spans[2].text, ' for info');

      // Link span should be underlined and have a tap recognizer.
      expect(spans[1].style?.decoration, TextDecoration.underline);
      expect(spans[1].recognizer, isA<TapGestureRecognizer>());
    });

    testWidgets('multiple URLs in one message', (tester) async {
      await tester.pumpWidget(_wrap(
        const LinkableText(
          text: 'See https://a.com and https://b.com ok',
          style: TextStyle(fontSize: 14, color: Colors.black),
          isMe: false,
        ),
      ));

      final spans = _extractSpans(tester);
      expect(spans.length, 5);
      expect(spans[0].text, 'See ');
      expect(spans[1].text, 'https://a.com');
      expect(spans[2].text, ' and ');
      expect(spans[3].text, 'https://b.com');
      expect(spans[4].text, ' ok');
    });

    testWidgets('URL at start of text', (tester) async {
      await tester.pumpWidget(_wrap(
        const LinkableText(
          text: 'https://start.com is cool',
          style: TextStyle(fontSize: 14, color: Colors.black),
          isMe: false,
        ),
      ));

      final spans = _extractSpans(tester);
      expect(spans.length, 2);
      expect(spans[0].text, 'https://start.com');
      expect(spans[1].text, ' is cool');
    });

    testWidgets('URL at end of text', (tester) async {
      await tester.pumpWidget(_wrap(
        const LinkableText(
          text: 'Go to https://end.com',
          style: TextStyle(fontSize: 14, color: Colors.black),
          isMe: false,
        ),
      ));

      final spans = _extractSpans(tester);
      expect(spans.length, 2);
      expect(spans[0].text, 'Go to ');
      expect(spans[1].text, 'https://end.com');
    });

    testWidgets('trailing punctuation not included in URL', (tester) async {
      await tester.pumpWidget(_wrap(
        const LinkableText(
          text: 'check https://example.com.',
          style: TextStyle(fontSize: 14, color: Colors.black),
          isMe: false,
        ),
      ));

      final spans = _extractSpans(tester);
      // Should be: "check ", "https://example.com", "."
      expect(spans.length, 3);
      expect(spans[0].text, 'check ');
      expect(spans[1].text, 'https://example.com');
      expect(spans[2].text, '.');
    });

    testWidgets('isMe uses different link color', (tester) async {
      await tester.pumpWidget(_wrap(
        const LinkableText(
          text: 'https://test.com',
          style: TextStyle(fontSize: 14, color: Colors.white),
          isMe: true,
        ),
      ));

      final spans = _extractSpans(tester);
      expect(spans.length, 1);
      expect(spans[0].style?.decoration, TextDecoration.underline);
      expect(spans[0].recognizer, isA<TapGestureRecognizer>());
    });

    testWidgets('http:// URLs are also detected', (tester) async {
      await tester.pumpWidget(_wrap(
        const LinkableText(
          text: 'old http://example.com link',
          style: TextStyle(fontSize: 14, color: Colors.black),
          isMe: false,
        ),
      ));

      final spans = _extractSpans(tester);
      expect(spans.length, 3);
      expect(spans[1].text, 'http://example.com');
      expect(spans[1].recognizer, isA<TapGestureRecognizer>());
    });
  });
}

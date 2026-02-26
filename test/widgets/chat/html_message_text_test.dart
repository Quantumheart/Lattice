import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/widgets/chat/html_message_text.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

/// Extracts all leaf [InlineSpan]s from the first [RichText] widget.
List<InlineSpan> _extractSpans(WidgetTester tester) {
  final richText = tester.widget<RichText>(find.byType(RichText).first);
  final root = richText.text as TextSpan;
  final inner = root.children?.first as TextSpan?;
  if (inner == null) return [root];
  if (inner.children == null || inner.children!.isEmpty) return [inner];
  return inner.children!.cast<InlineSpan>();
}

/// Recursively flattens an [InlineSpan] tree into leaf [TextSpan]s.
List<TextSpan> _flattenTextSpans(InlineSpan span) {
  if (span is TextSpan) {
    if (span.children == null || span.children!.isEmpty) {
      return [span];
    }
    return span.children!.expand(_flattenTextSpans).toList();
  }
  return [];
}

/// Extracts all leaf [TextSpan]s from the widget tree (flattened).
List<TextSpan> _extractFlatSpans(WidgetTester tester) {
  final spans = _extractSpans(tester);
  return spans.expand(_flattenTextSpans).toList();
}

void main() {
  group('HtmlMessageText', () {
    testWidgets('plain text without HTML tags renders as-is', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: 'Hello world, no tags here',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans.length, 1);
      expect(spans[0].text, 'Hello world, no tags here');
    });

    testWidgets('bold tags render with FontWeight.bold', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<b>bold</b> normal',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans.length, 2);
      expect(spans[0].text, 'bold');
      expect(spans[0].style?.fontWeight, FontWeight.bold);
      expect(spans[1].text, ' normal');
    });

    testWidgets('<strong> renders bold', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<strong>strong</strong>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans[0].text, 'strong');
      expect(spans[0].style?.fontWeight, FontWeight.bold);
    });

    testWidgets('italic tags render with FontStyle.italic', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<i>italic</i> and <em>emphasis</em>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans[0].text, 'italic');
      expect(spans[0].style?.fontStyle, FontStyle.italic);
      expect(spans[2].text, 'emphasis');
      expect(spans[2].style?.fontStyle, FontStyle.italic);
    });

    testWidgets('strikethrough tags render lineThrough', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<s>strike</s> <del>deleted</del> <strike>old</strike>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans[0].text, 'strike');
      expect(spans[0].style?.decoration, TextDecoration.lineThrough);
      expect(spans[2].text, 'deleted');
      expect(spans[2].style?.decoration, TextDecoration.lineThrough);
      expect(spans[4].text, 'old');
      expect(spans[4].style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('underline tags render with underline', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<u>underlined</u> <ins>inserted</ins>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans[0].text, 'underlined');
      expect(spans[0].style?.decoration, TextDecoration.underline);
      expect(spans[2].text, 'inserted');
      expect(spans[2].style?.decoration, TextDecoration.underline);
    });

    testWidgets('nested bold+italic tags', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<b><i>bold italic</i></b>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans[0].text, 'bold italic');
      expect(spans[0].style?.fontWeight, FontWeight.bold);
      expect(spans[0].style?.fontStyle, FontStyle.italic);
    });

    testWidgets('<a href> renders tappable underlined link', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: 'Visit <a href="https://example.com">example</a> now',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans.length, 3);
      expect(spans[0].text, 'Visit ');
      expect(spans[1].text, 'example');
      expect(spans[1].style?.decoration, TextDecoration.underline);
      expect(spans[1].recognizer, isA<TapGestureRecognizer>());
      expect(spans[2].text, ' now');
    });

    testWidgets('<br> produces newline', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: 'line one<br>line two',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans.length, 3);
      expect(spans[0].text, 'line one');
      expect(spans[1].text, '\n');
      expect(spans[2].text, 'line two');
    });

    testWidgets('<p> tags produce double newlines between paragraphs',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<p>First paragraph</p><p>Second paragraph</p>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      // First paragraph content, then \n\n, then second paragraph content.
      final allText = spans.map((s) => s.text ?? '').join();
      expect(allText, contains('First paragraph'));
      expect(allText, contains('Second paragraph'));
      expect(allText, contains('\n\n'));
    });

    testWidgets('headings render bold with scaled font size', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<h1>Big heading</h1>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans[0].text, 'Big heading');
      expect(spans[0].style?.fontWeight, FontWeight.bold);
      // h1 scale = 1.6, so 14 * 1.6 = 22.4
      expect(spans[0].style?.fontSize, closeTo(22.4, 0.01));
    });

    testWidgets('<ol> and <ul> with <li> items', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<ol><li>First</li><li>Second</li></ol>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      final allText = spans.map((s) => s.text ?? '').join();
      expect(allText, contains('1. First'));
      expect(allText, contains('2. Second'));
    });

    testWidgets('unordered list uses bullet points', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<ul><li>Apple</li><li>Banana</li></ul>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      final allText = spans.map((s) => s.text ?? '').join();
      expect(allText, contains('• Apple'));
      expect(allText, contains('• Banana'));
    });

    testWidgets('<blockquote> renders with italic style', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<blockquote>quoted text</blockquote>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      // Blockquote uses a WidgetSpan containing a Container with an inner
      // Text.rich. Find all RichText widgets and inspect the inner one.
      final richTexts =
          tester.widgetList<RichText>(find.byType(RichText)).toList();
      expect(richTexts.length, greaterThanOrEqualTo(2));
      final innerRich = richTexts.last;
      final innerRoot = innerRich.text as TextSpan;
      // Collect all leaf text spans.
      List<TextSpan> collectLeaves(TextSpan span) {
        if (span.children == null || span.children!.isEmpty) return [span];
        return span.children!
            .whereType<TextSpan>()
            .expand(collectLeaves)
            .toList();
      }

      final leaves = collectLeaves(innerRoot);
      final textLeaf = leaves.firstWhere((s) => s.text == 'quoted text');
      expect(textLeaf.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('<mx-reply> content is stripped', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html:
              '<mx-reply><blockquote>reply content</blockquote></mx-reply>Actual message',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      final allText = spans.map((s) => s.text ?? '').join();
      expect(allText, 'Actual message');
      expect(allText, isNot(contains('reply content')));
    });

    testWidgets('unsupported tags degrade gracefully', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<custom>preserved text</custom>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans[0].text, 'preserved text');
    });

    testWidgets('URLs in plain text nodes are auto-linked', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: '<b>Check https://example.com here</b>',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans.length, 3);
      expect(spans[0].text, 'Check ');
      expect(spans[1].text, 'https://example.com');
      expect(spans[1].style?.decoration, TextDecoration.underline);
      expect(spans[1].recognizer, isA<TapGestureRecognizer>());
      expect(spans[2].text, ' here');
    });

    testWidgets('<code> renders with monospace font', (tester) async {
      await tester.pumpWidget(_wrap(
        const HtmlMessageText(
          html: 'Use <code>flutter run</code> to start',
          style: TextStyle(fontSize: 14),
          isMe: false,
        ),
      ));

      final spans = _extractFlatSpans(tester);
      expect(spans.length, 3);
      expect(spans[0].text, 'Use ');
      expect(spans[1].text, 'flutter run');
      expect(spans[1].style?.fontFamily, 'monospace');
      expect(spans[2].text, ' to start');
    });
  });
}

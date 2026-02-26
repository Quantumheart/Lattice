import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/widgets/chat/code_block.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('CodeBlock', () {
    testWidgets('renders code text', (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'print("hello")',
          isMe: false,
        ),
      ));

      // Code is rendered via Text.rich with TextSpan children.
      // Find a RichText whose text tree contains 'print("hello")'.
      final richTexts =
          tester.widgetList<RichText>(find.byType(RichText)).toList();
      final codeRichText = richTexts.where((rt) {
        final span = rt.text as TextSpan;
        return span.toPlainText().contains('print("hello")');
      });
      expect(codeRichText, isNotEmpty);
    });

    testWidgets('displays language label when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'void main() {}',
          language: 'dart',
          isMe: false,
        ),
      ));

      // Language label is a plain Text widget with the language name.
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      final languageLabel = textWidgets.where(
        (t) => t.data == 'dart',
      );
      expect(languageLabel, isNotEmpty);
    });

    testWidgets('hides language label when language is null', (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'some code',
          isMe: false,
        ),
      ));

      // There should be no Text widget for a language label.
      // All Text widgets should either be empty or part of the code rendering.
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      final languageLabels = textWidgets.where((t) {
        // Language labels are plain Text with string data, not Text.rich.
        // The code is rendered via Text.rich, so data will be null for it.
        return t.data != null && t.data!.isNotEmpty;
      });
      expect(languageLabels, isEmpty);
    });

    testWidgets('copy button is present', (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'const x = 42;',
          language: 'dart',
          isMe: false,
        ),
      ));

      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byTooltip('Copy code'), findsOneWidget);
    });

    testWidgets('copy button copies code to clipboard', (tester) async {
      // Set up clipboard mock.
      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardContent =
                (call.arguments as Map<String, dynamic>)['text'] as String;
          }
          return null;
        },
      );

      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'const x = 42;',
          language: 'dart',
          isMe: false,
        ),
      ));

      await tester.tap(find.byIcon(Icons.copy_rounded));
      await tester.pumpAndSettle();

      expect(clipboardContent, 'const x = 42;');
      expect(find.text('Copied to clipboard'), findsOneWidget);

      // Clean up mock.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    testWidgets('horizontal scrolling is enabled', (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'a very long line of code that should scroll horizontally '
              'when it exceeds the container width',
          isMe: false,
        ),
      ));

      final scrollViews = tester.widgetList<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      final horizontalScroll = scrollViews.where(
        (sv) => sv.scrollDirection == Axis.horizontal,
      );
      expect(horizontalScroll, isNotEmpty);
    });

    testWidgets('renders with monospace font', (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'fn main() {}',
          language: 'rust',
          isMe: false,
        ),
      ));

      // Find RichText widgets that have monospace font in their root span.
      final richTexts =
          tester.widgetList<RichText>(find.byType(RichText)).toList();
      final codeRichText = richTexts.firstWhere(
        (rt) => (rt.text as TextSpan).style?.fontFamily == 'monospace',
      );
      expect(codeRichText, isNotNull);
    });

    testWidgets('uses appropriate background for isMe=true', (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'hello',
          isMe: true,
        ),
      ));

      // The outermost Container should have a background color.
      final containers = tester.widgetList<Container>(
        find.byType(Container),
      );
      final codeContainer = containers.firstWhere(
        (c) => c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(8),
      );
      final decoration = codeContainer.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
    });

    testWidgets('uses appropriate background for isMe=false', (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'hello',
          isMe: false,
        ),
      ));

      final containers = tester.widgetList<Container>(
        find.byType(Container),
      );
      final codeContainer = containers.firstWhere(
        (c) => c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(8),
      );
      final decoration = codeContainer.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
    });

    testWidgets('renders empty code block gracefully', (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: '',
          isMe: false,
        ),
      ));

      // Should render without crashing.
      expect(find.byType(CodeBlock), findsOneWidget);
    });

    testWidgets('applies syntax highlighting with colored spans',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const CodeBlock(
          code: 'void main() {\n  print("hello");\n}',
          language: 'dart',
          isMe: false,
        ),
      ));

      // Find the RichText that contains the code (has monospace font).
      final richTexts =
          tester.widgetList<RichText>(find.byType(RichText)).toList();
      final codeRichText = richTexts.firstWhere(
        (rt) => (rt.text as TextSpan).style?.fontFamily == 'monospace',
      );
      final rootSpan = codeRichText.text as TextSpan;

      // The children should have multiple spans with different styles
      // (syntax highlighting produces colored spans).
      expect(rootSpan.children, isNotNull);
      expect(rootSpan.children!.length, greaterThan(1));

      // At least some spans should have non-null styles with colors set
      // (indicating syntax highlighting was applied).
      final styledSpans = rootSpan.children!
          .whereType<TextSpan>()
          .where((s) => s.style?.color != null || s.style?.fontWeight != null);
      expect(styledSpans, isNotEmpty);
    });
  });
}

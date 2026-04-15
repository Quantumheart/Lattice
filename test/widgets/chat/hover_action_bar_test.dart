import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/widgets/hover_action_bar.dart';

void main() {
  Widget buildTestWidget({
    VoidCallback? onReact,
    void Function(String emoji)? onQuickReact,
    VoidCallback? onReply,
    void Function(Offset position)? onMore,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoverActionBar(
            cs: const ColorScheme.light(),
            onReact: onReact,
            onQuickReact: onQuickReact,
            onReply: onReply,
            onMore: onMore ?? (_) {},
          ),
        ),
      ),
    );
  }

  group('HoverActionBar', () {
    testWidgets('shows more icon always', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('shows react icon when onQuickReact provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(onQuickReact: (_) {}));
      expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);
    });

    testWidgets('hides react icon when no react callbacks', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
    });

    testWidgets('shows reply icon when onReply provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(onReply: () {}));
      expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
    });

    testWidgets('hides reply icon when onReply is null', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.reply_rounded), findsNothing);
    });

    testWidgets('tap reply calls onReply', (tester) async {
      var called = false;
      await tester.pumpWidget(buildTestWidget(onReply: () => called = true));

      await tester.tap(find.byIcon(Icons.reply_rounded));
      expect(called, isTrue);
    });

    testWidgets('tap more calls onMore', (tester) async {
      Offset? pos;
      await tester.pumpWidget(buildTestWidget(onMore: (p) => pos = p));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      expect(pos, isNotNull);
    });

    testWidgets('tap react icon opens quick-react overlay with emojis',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(onQuickReact: (_) {}));

      await tester.tap(find.byIcon(Icons.add_reaction_outlined));
      await tester.pumpAndSettle();

      expect(find.text('\u{2764}\u{FE0F}'), findsOneWidget);
      expect(find.text('\u{1F44D}'), findsOneWidget);
      expect(find.text('\u{1F44E}'), findsOneWidget);
      expect(find.text('\u{1F602}'), findsOneWidget);
      expect(find.text('\u{1F622}'), findsOneWidget);
      expect(find.text('\u{1F62E}'), findsOneWidget);
    });

    testWidgets('tap emoji in overlay calls onQuickReact and closes overlay',
        (tester) async {
      String? selectedEmoji;
      await tester.pumpWidget(
        buildTestWidget(onQuickReact: (e) => selectedEmoji = e),
      );

      await tester.tap(find.byIcon(Icons.add_reaction_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('\u{1F44D}'));
      await tester.pumpAndSettle();

      expect(selectedEmoji, '\u{1F44D}');
      expect(find.text('\u{1F602}'), findsNothing);
    });
  });
}

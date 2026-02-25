import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/widgets/chat/swipeable_message.dart';

void main() {
  group('SwipeableMessage', () {
    testWidgets('triggers reply on swipe past threshold', (tester) async {
      var replyCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableMessage(
              onReply: () => replyCalled = true,
              child: const SizedBox(
                width: 200,
                height: 50,
                child: Text('Test message'),
              ),
            ),
          ),
        ),
      );

      // Swipe right past the 64px trigger threshold.
      await tester.drag(find.text('Test message'), const Offset(80, 0));
      await tester.pumpAndSettle();

      expect(replyCalled, isTrue);
    });

    testWidgets('does not trigger reply on short swipe', (tester) async {
      var replyCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableMessage(
              onReply: () => replyCalled = true,
              child: const SizedBox(
                width: 200,
                height: 50,
                child: Text('Test message'),
              ),
            ),
          ),
        ),
      );

      // Swipe right but below the threshold.
      await tester.drag(find.text('Test message'), const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(replyCalled, isFalse);
    });

    testWidgets('snaps back to origin after swipe', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableMessage(
              onReply: () {},
              child: const SizedBox(
                width: 200,
                height: 50,
                child: Text('Test message'),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.text('Test message'), const Offset(80, 0));
      await tester.pumpAndSettle();

      // After animation settles, the Transform.translate (descendant of
      // SwipeableMessage) should have offset back to 0.
      final transform = tester.widget<Transform>(
        find.descendant(
          of: find.byType(SwipeableMessage),
          matching: find.byType(Transform),
        ).last,
      );
      expect(transform.transform.storage[12], 0.0);
    });

    testWidgets('shows reply icon during swipe', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableMessage(
              onReply: () {},
              child: const SizedBox(
                width: 200,
                height: 50,
                child: Text('Test message'),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
    });

    testWidgets('does not trigger on leftward swipe', (tester) async {
      var replyCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableMessage(
              onReply: () => replyCalled = true,
              child: const SizedBox(
                width: 200,
                height: 50,
                child: Text('Test message'),
              ),
            ),
          ),
        ),
      );

      // Swipe left (negative offset) — should be clamped to 0.
      await tester.drag(find.text('Test message'), const Offset(-80, 0));
      await tester.pumpAndSettle();

      expect(replyCalled, isFalse);
    });
  });
}

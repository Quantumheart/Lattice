import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/widgets/chat/mention_pill.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('MentionPill', () {
    testWidgets('user mention shows @-prefixed display name', (tester) async {
      await tester.pumpWidget(_wrap(
        const MentionPill(
          displayName: 'Alice',
          matrixId: '@alice:example.com',
          type: MentionType.user,
          isMe: false,
          style: TextStyle(fontSize: 14),
        ),
      ));

      expect(find.text('@Alice'), findsOneWidget);
    });

    testWidgets('room mention shows #-prefixed display name', (tester) async {
      await tester.pumpWidget(_wrap(
        const MentionPill(
          displayName: 'general',
          matrixId: '#general:example.com',
          type: MentionType.room,
          isMe: false,
          style: TextStyle(fontSize: 14),
        ),
      ));

      expect(find.text('#general'), findsOneWidget);
    });

    testWidgets('does not double-prefix when displayName starts with @',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const MentionPill(
          displayName: '@Alice',
          matrixId: '@alice:example.com',
          type: MentionType.user,
          isMe: false,
          style: TextStyle(fontSize: 14),
        ),
      ));

      expect(find.text('@Alice'), findsOneWidget);
      expect(find.text('@@Alice'), findsNothing);
    });

    testWidgets('does not double-prefix when displayName starts with #',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const MentionPill(
          displayName: '#general',
          matrixId: '#general:example.com',
          type: MentionType.room,
          isMe: false,
          style: TextStyle(fontSize: 14),
        ),
      ));

      expect(find.text('#general'), findsOneWidget);
      expect(find.text('##general'), findsNothing);
    });

    testWidgets('pill has rounded decoration', (tester) async {
      await tester.pumpWidget(_wrap(
        const MentionPill(
          displayName: 'Alice',
          matrixId: '@alice:example.com',
          type: MentionType.user,
          isMe: false,
          style: TextStyle(fontSize: 14),
        ),
      ));

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('@Alice'),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(12));
    });

    testWidgets('font size is scaled down from parent style', (tester) async {
      await tester.pumpWidget(_wrap(
        const MentionPill(
          displayName: 'Alice',
          matrixId: '@alice:example.com',
          type: MentionType.user,
          isMe: false,
          style: TextStyle(fontSize: 14),
        ),
      ));

      final text = tester.widget<Text>(find.text('@Alice'));
      // 14 * 0.92 = 12.88
      expect(text.style?.fontSize, closeTo(12.88, 0.01));
      expect(text.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('onTap callback is invoked', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(_wrap(
        MentionPill(
          displayName: 'Alice',
          matrixId: '@alice:example.com',
          type: MentionType.user,
          isMe: false,
          style: const TextStyle(fontSize: 14),
          onTap: () => tapCount++,
        ),
      ));

      await tester.tap(find.text('@Alice'));
      expect(tapCount, 1);
    });
  });
}

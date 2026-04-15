import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/settings/widgets/push_to_talk_key_editor.dart';

void main() {
  late int capturedKeyId;

  Widget buildEditor({int? keyId}) {
    capturedKeyId = keyId ?? LogicalKeyboardKey.controlLeft.keyId;
    return MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            return PushToTalkKeyEditor(
              keyId: capturedKeyId,
              onKeyChanged: (id) => setState(() => capturedKeyId = id),
            );
          },
        ),
      ),
    );
  }

  testWidgets('displays current key label', (tester) async {
    await tester.pumpWidget(buildEditor());
    await tester.pumpAndSettle();

    expect(find.text('Control Left'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('tapping Edit shows capture dialog', (tester) async {
    await tester.pumpWidget(buildEditor());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Set push-to-talk key'), findsOneWidget);
    expect(find.textContaining('Press a key'), findsOneWidget);
  });

  testWidgets('pressing Escape cancels capture without changing key',
      (tester) async {
    final originalKeyId = LogicalKeyboardKey.controlLeft.keyId;
    await tester.pumpWidget(buildEditor(keyId: originalKeyId));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Set push-to-talk key'), findsNothing);
    expect(capturedKeyId, originalKeyId);
  });

  testWidgets('pressing a key in capture mode updates key', (tester) async {
    await tester.pumpWidget(buildEditor());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(find.text('Set push-to-talk key'), findsNothing);
    expect(capturedKeyId, LogicalKeyboardKey.space.keyId);
  });
}

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/widgets/chat/compose_bar.dart';

Widget _wrap({
  required TextEditingController controller,
  required VoidCallback onSend,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ComposeBar(
        controller: controller,
        onSend: onSend,
        onCancelReply: () {},
      ),
    ),
  );
}

void main() {
  group('ComposeBar', () {
    late TextEditingController controller;

    setUp(() {
      controller = TextEditingController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('Enter key sends message when text is non-empty',
        (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ));

      // Type some text.
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      // Press Enter.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 1);
    });

    testWidgets('Enter key does not send when text is empty', (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ));

      // Press Enter with empty text.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 0);
    });

    testWidgets('Enter key does not send when text is only whitespace',
        (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ));

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 0);
    });

    testWidgets('Shift+Enter does not trigger send', (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ));

      await tester.enterText(find.byType(TextField), 'line one');
      await tester.pump();

      // Press Shift+Enter — should not trigger send.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(sendCount, 0);
    });

    testWidgets('send button calls onSend when text is present',
        (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ));

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(sendCount, 1);
    });

    testWidgets('send button is disabled when text is empty', (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ));

      // Find the send IconButton wrapping the send icon.
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.send_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Ctrl/Cmd+Up moves cursor to start of text', (tester) async {
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
      ));

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();

      // Cursor is at end after entering text. Press Ctrl/Cmd+Up.
      final modifier = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();

      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 0);
    });

    testWidgets('Ctrl/Cmd+Down moves cursor to end of text', (tester) async {
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
      ));

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();

      // Move cursor to start first.
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      // Press Ctrl/Cmd+Down.
      final modifier = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();

      expect(controller.selection.baseOffset, 'hello world'.length);
      expect(controller.selection.extentOffset, 'hello world'.length);
    });

    testWidgets('TextField uses newline text input action', (tester) async {
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
      ));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.textInputAction, TextInputAction.newline);
    });
  });
}

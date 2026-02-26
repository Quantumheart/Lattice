import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:lattice/widgets/chat/compose_bar.dart';
import 'package:lattice/widgets/chat/mention_suggestion_overlay.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<User>(),
  MockSpec<Client>(),
])
import 'compose_bar_test.mocks.dart';

Widget _wrap({
  required TextEditingController controller,
  required VoidCallback onSend,
  Room? room,
  List<Room>? joinedRooms,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ComposeBar(
        controller: controller,
        onSend: onSend,
        onCancelReply: () {},
        room: room,
        joinedRooms: joinedRooms,
      ),
    ),
  );
}

MockUser _makeUser(String id, String? displayName) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  when(user.avatarUrl).thenReturn(null);
  return user;
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

  group('ComposeBar with mention autocomplete', () {
    late TextEditingController controller;
    late MockRoom mockRoom;
    late MockClient mockClient;
    late List<MockUser> members;

    setUp(() {
      controller = TextEditingController();
      mockRoom = MockRoom();
      mockClient = MockClient();

      members = [
        _makeUser('@alice:example.com', 'Alice'),
        _makeUser('@bob:example.com', 'Bob'),
      ];

      when(mockRoom.client).thenReturn(mockClient);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.getParticipants()).thenReturn(members);
      when(mockRoom.requestParticipants())
          .thenAnswer((_) async => members);
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('typing @ shows suggestion list', (tester) async {
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
        room: mockRoom,
        joinedRooms: [],
      ));

      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();

      expect(find.byType(MentionSuggestionList), findsOneWidget);
    });

    testWidgets('Enter sends when autocomplete is active but empty',
        (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
        room: mockRoom,
        joinedRooms: [],
      ));

      // Type a query that matches nothing.
      await tester.enterText(find.byType(TextField), '@zzzznotamember');
      await tester.pump();

      // Suggestion list should not be shown (empty suggestions).
      expect(find.byType(MentionSuggestionList), findsNothing);

      // Enter should send the message.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 1);
    });

    testWidgets('Enter confirms selection when suggestions are visible',
        (tester) async {
      int sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
        room: mockRoom,
        joinedRooms: [],
      ));

      await tester.enterText(find.byType(TextField), '@ali');
      await tester.pump();

      expect(find.byType(MentionSuggestionList), findsOneWidget);

      // Press Enter — should confirm selection, not send.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 0);
      expect(controller.text, '@Alice ');
    });

    testWidgets('tapping a suggestion inserts mention', (tester) async {
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
        room: mockRoom,
        joinedRooms: [],
      ));

      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();

      // Tap on Alice suggestion.
      await tester.tap(find.text('Alice'));
      await tester.pump();

      expect(controller.text, '@Alice ');
    });

    testWidgets('Escape dismisses suggestions', (tester) async {
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
        room: mockRoom,
        joinedRooms: [],
      ));

      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();

      expect(find.byType(MentionSuggestionList), findsOneWidget);

      // Press Escape.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(MentionSuggestionList), findsNothing);
    });
  });
}

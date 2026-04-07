import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/chat/services/typing_controller.dart';
import 'package:lattice/features/chat/widgets/compose_bar.dart';
import 'package:lattice/features/chat/widgets/mention_suggestion_overlay.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<User>(),
  MockSpec<Client>(),
  MockSpec<TypingController>(),
])
import 'compose_bar_test.mocks.dart';

Widget _wrap({
  required TextEditingController controller,
  required VoidCallback onSend,
  Room? room,
  List<Room>? joinedRooms,
  PreferencesService? prefs,
  TypingController? typingController,
}) {
  return ChangeNotifierProvider<PreferencesService>.value(
    value: prefs ?? PreferencesService(),
    child: MaterialApp(
      home: Scaffold(
        body: ComposeBar(
          controller: controller,
          onSend: onSend,
          onCancelReply: () {},
          onCancelEdit: () {},
          room: room,
          joinedRooms: joinedRooms,
          typingController: typingController,
          onRemoveAttachment: (_) {},
          onClearAttachments: () {},
        ),
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
      var sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ),);

      // Type some text.
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      // Press Enter.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 1);
    });

    testWidgets('Enter key does not send when text is empty', (tester) async {
      var sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ),);

      // Press Enter with empty text.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 0);
    });

    testWidgets('Enter key does not send when text is only whitespace',
        (tester) async {
      var sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ),);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sendCount, 0);
    });

    testWidgets('Shift+Enter does not trigger send', (tester) async {
      var sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ),);

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
      var sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ),);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(sendCount, 1);
    });

    testWidgets('send button is disabled when text is empty', (tester) async {
      var sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
      ),);

      // Find the send IconButton wrapping the send icon.
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.send_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Ctrl/Cmd+Up binding registered for jump to start',
        (tester) async {
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
      ),);

      final shortcuts = tester.widget<CallbackShortcuts>(
        find.byType(CallbackShortcuts),
      );
      final hasUpBinding = shortcuts.bindings.keys.any(
        (a) =>
            a is SingleActivator &&
            a.trigger == LogicalKeyboardKey.arrowUp &&
            (a.meta || a.control),
      );
      expect(hasUpBinding, isTrue);
    });

    testWidgets('Ctrl/Cmd+Down binding registered for jump to end',
        (tester) async {
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
      ),);

      final shortcuts = tester.widget<CallbackShortcuts>(
        find.byType(CallbackShortcuts),
      );
      final hasDownBinding = shortcuts.bindings.keys.any(
        (a) =>
            a is SingleActivator &&
            a.trigger == LogicalKeyboardKey.arrowDown &&
            (a.meta || a.control),
      );
      expect(hasDownBinding, isTrue);
    });

    testWidgets('TextField uses newline text input action', (tester) async {
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
      ),);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.textInputAction, TextInputAction.newline);
    });

    testWidgets('typing indicator not sent when preference is disabled',
        (tester) async {
      SharedPreferences.setMockInitialValues({'typing_indicators': false});
      final sp = await SharedPreferences.getInstance();
      final prefs = PreferencesService(prefs: sp);
      final mockTyping = MockTypingController();

      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () {},
        prefs: prefs,
        typingController: mockTyping,
      ),);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      verifyNever(mockTyping.onTextChanged(any));
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
      ),);

      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();

      expect(find.byType(MentionSuggestionList), findsOneWidget);
    });

    testWidgets('Enter sends when autocomplete is active but empty',
        (tester) async {
      var sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
        room: mockRoom,
        joinedRooms: [],
      ),);

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
      var sendCount = 0;
      await tester.pumpWidget(_wrap(
        controller: controller,
        onSend: () => sendCount++,
        room: mockRoom,
        joinedRooms: [],
      ),);

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
      ),);

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
      ),);

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

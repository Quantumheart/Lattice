import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/services/preferences_service.dart';
import 'package:lattice/screens/chat_screen.dart';
import 'package:lattice/widgets/chat/message_bubble.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
  MockSpec<Event>(),
  MockSpec<User>(),
])
import 'message_reply_test.mocks.dart';

void main() {
  // ── Unit tests for stripReplyFallback ─────────────────────

  group('stripReplyFallback', () {
    test('strips standard reply fallback lines', () {
      const body = '> <@alice:example.com> Hello\n> world\n\nMy reply';
      expect(stripReplyFallback(body), 'My reply');
    });

    test('strips bare > lines (no trailing space)', () {
      const body = '> <@alice:example.com> Hello\n>\n\nMy reply';
      expect(stripReplyFallback(body), 'My reply');
    });

    test('returns body unchanged when no fallback present', () {
      const body = 'Just a normal message';
      expect(stripReplyFallback(body), 'Just a normal message');
    });

    test('handles empty body', () {
      expect(stripReplyFallback(''), '');
    });

    test('handles body that is only fallback lines', () {
      const body = '> quoted line 1\n> quoted line 2';
      expect(stripReplyFallback(body), '');
    });

    test('preserves multiline content after fallback', () {
      const body = '> fallback\n\nLine 1\nLine 2';
      expect(stripReplyFallback(body), 'Line 1\nLine 2');
    });

    test('strips blank separator line after fallback block', () {
      const body = '> quote\n\nactual message';
      expect(stripReplyFallback(body), 'actual message');
    });
  });

  // ── Widget tests for reply flow ───────────────────────────

  group('ChatScreen reply flow', () {
    late MockClient mockClient;
    late MockMatrixService mockMatrix;
    late MockRoom mockRoom;
    late MockTimeline mockTimeline;
    late PreferencesService prefsService;

    MockEvent makeEvent({
      required String eventId,
      required String senderId,
      String body = 'Hello',
      Map<String, Object?>? content,
    }) {
      final event = MockEvent();
      when(event.eventId).thenReturn(eventId);
      when(event.senderId).thenReturn(senderId);
      when(event.body).thenReturn(body);
      when(event.type).thenReturn(EventTypes.Message);
      when(event.messageType).thenReturn(MessageTypes.Text);
      when(event.originServerTs).thenReturn(DateTime(2025, 1, 1, 12, 0));
      when(event.status).thenReturn(EventStatus.synced);
      when(event.content)
          .thenReturn(content ?? {'body': body, 'msgtype': 'm.text'});
      when(event.room).thenReturn(mockRoom);

      final sender = MockUser();
      when(sender.displayName).thenReturn(
          senderId.split(':').first.substring(1));
      when(sender.avatarUrl).thenReturn(null);
      when(event.senderFromMemoryOrFallback).thenReturn(sender);

      return event;
    }

    setUp(() {
      mockClient = MockClient();
      mockMatrix = MockMatrixService();
      mockRoom = MockRoom();
      mockTimeline = MockTimeline();
      prefsService = PreferencesService();

      when(mockMatrix.client).thenReturn(mockClient);
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockClient.userID).thenReturn('@me:example.com');
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.summary).thenReturn(
        RoomSummary.fromJson({'m.joined_member_count': 3}),
      );
      when(mockTimeline.canRequestHistory).thenReturn(false);
    });

    Widget buildTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
          ChangeNotifierProvider<PreferencesService>.value(
              value: prefsService),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 400, // mobile width to test swipe path
            child: ChatScreen(roomId: '!room:example.com'),
          ),
        ),
      );
    }

    testWidgets('reply preview banner appears after triggering reply',
        (tester) async {
      // Set mobile screen size so SwipeableMessage is used.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = makeEvent(
        eventId: '\$evt1',
        senderId: '@alice:example.com',
        body: 'Hello world',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // No reply banner initially.
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // Simulate swipe-to-reply on mobile by dragging right.
      final messageFinder = find.text('Hello world');
      expect(messageFinder, findsOneWidget);

      await tester.drag(messageFinder, const Offset(80, 0));
      await tester.pumpAndSettle();

      // Reply preview banner should now be visible with the sender name.
      expect(find.text('alice'), findsWidgets);
      // Close button should be visible.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('cancel reply removes the preview banner', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = makeEvent(
        eventId: '\$evt1',
        senderId: '@alice:example.com',
        body: 'Hello world',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Trigger reply via swipe.
      await tester.drag(find.text('Hello world'), const Offset(80, 0));
      await tester.pumpAndSettle();

      // Cancel the reply.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Banner should be gone.
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('failed send restores reply state', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = makeEvent(
        eventId: '\$evt1',
        senderId: '@alice:example.com',
        body: 'Hello world',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);
      when(mockRoom.sendTextEvent(any, inReplyTo: anyNamed('inReplyTo')))
          .thenThrow(Exception('Network error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Trigger reply.
      await tester.drag(find.text('Hello world'), const Offset(80, 0));
      await tester.pumpAndSettle();

      // Type a message and send.
      await tester.enterText(find.byType(TextField), 'My reply');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      // Reply banner should still be visible after failed send.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });
}

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/chat/screens/chat_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

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

    test('strips nested reply fallback (reply to a reply)', () {
      const body = '> <@bob:example.com> > <@alice:example.com> Hi\n> reply text\n\nMy reply';
      expect(stripReplyFallback(body), 'My reply');
    });

    test('preserves body text starting with > that is not a fallback', () {
      // A message that starts with > but is user-written quoting, not
      // part of a reply fallback block — only lines at the very start
      // that match the fallback pattern are stripped.
      const body = 'Normal start\n> user quote';
      expect(stripReplyFallback(body), 'Normal start\n> user quote');
    });
  });

  // ── Widget tests for reply flow ───────────────────────────

  group('ChatScreen reply flow', () {
    late MockClient mockClient;
    late MockMatrixService mockMatrix;
    late MockRoom mockRoom;
    late MockTimeline mockTimeline;
    late PreferencesService prefsService;
    late SelectionService selectionService;

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
      when(event.originServerTs).thenReturn(DateTime(2025, 1, 1, 12));
      when(event.status).thenReturn(EventStatus.synced);
      when(event.content)
          .thenReturn(content ?? {'body': body, 'msgtype': 'm.text'});
      when(event.room).thenReturn(mockRoom);

      final sender = MockUser();
      when(sender.displayName).thenReturn(
          senderId.split(':').first.substring(1),);
      when(sender.avatarUrl).thenReturn(null);
      when(event.senderFromMemoryOrFallback).thenReturn(sender);
      when(event.getDisplayEvent(any)).thenReturn(event);
      when(event.hasAggregatedEvents(any, any)).thenReturn(false);
      when(event.formattedText).thenReturn('');

      return event;
    }

    setUp(() {
      mockClient = MockClient();
      mockMatrix = MockMatrixService();
      mockRoom = MockRoom();
      mockTimeline = MockTimeline();
      prefsService = PreferencesService();

      when(mockClient.onSync).thenReturn(CachedStreamController());
      when(mockClient.rooms).thenReturn([]);
      selectionService = SelectionService(client: mockClient);

      when(mockMatrix.client).thenReturn(mockClient);
      when(mockMatrix.selection).thenReturn(selectionService);
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockClient.userID).thenReturn('@me:example.com');
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.receiptState).thenReturn(LatestReceiptState.empty());
      when(mockRoom.summary).thenReturn(
        RoomSummary.fromJson({'m.joined_member_count': 3}),
      );
      when(mockRoom.client).thenReturn(mockClient);
      when(mockTimeline.canRequestHistory).thenReturn(false);
    });

    Widget buildTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
          ChangeNotifierProvider<SelectionService>.value(value: selectionService),
          ChangeNotifierProvider(create: (ctx) => CallService(client: ctx.read<MatrixService>().client)),
          ChangeNotifierProvider<PreferencesService>.value(
              value: prefsService,),
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
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = makeEvent(
        eventId: r'$evt1',
        senderId: '@alice:example.com',
        body: 'Hello world',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(eventContextId: anyNamed('eventContextId'), onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // Hover over message to show action bar, then tap reply.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      final messageFinder = find.text('Hello world');
      expect(messageFinder, findsOneWidget);
      await gesture.moveTo(tester.getCenter(messageFinder));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.reply_rounded));
      await tester.pumpAndSettle();

      expect(find.text('alice'), findsWidgets);
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
        eventId: r'$evt1',
        senderId: '@alice:example.com',
        body: 'Hello world',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(eventContextId: anyNamed('eventContextId'), onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Trigger reply via hover action bar.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Hello world')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.reply_rounded));
      await tester.pumpAndSettle();

      // Cancel the reply.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

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
        eventId: r'$evt1',
        senderId: '@alice:example.com',
        body: 'Hello world',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(eventContextId: anyNamed('eventContextId'), onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);
      when(mockRoom.sendTextEvent(any,
              inReplyTo: anyNamed('inReplyTo'),
              editEventId: anyNamed('editEventId'),),)
          .thenThrow(Exception('Network error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Trigger reply via hover action bar.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Hello world')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.reply_rounded));
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

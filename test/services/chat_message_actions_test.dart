import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/chat/services/chat_message_actions.dart';
import 'package:lattice/features/chat/services/compose_state_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<Event>(),
  MockSpec<Timeline>(),
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<ScaffoldMessengerState>(),
])
import 'chat_message_actions_test.mocks.dart';

void main() {
  late MockRoom mockRoom;
  late MockEvent mockEvent;
  late MockTimeline mockTimeline;
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockScaffoldMessengerState mockScaffold;
  late ComposeStateController compose;
  late TextEditingController msgCtrl;
  late ChatMessageActions actions;

  setUp(() {
    mockRoom = MockRoom();
    mockEvent = MockEvent();
    mockTimeline = MockTimeline();
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockScaffold = MockScaffoldMessengerState();
    compose = ComposeStateController();
    msgCtrl = TextEditingController();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockEvent.room).thenReturn(mockRoom);
    when(mockEvent.eventId).thenReturn(r'$event1');
    actions = ChatMessageActions(
      getRoomId: () => '!room:example.com',
      getRoom: () => mockRoom,
      getTimeline: () => mockTimeline,
      compose: compose,
      msgCtrl: msgCtrl,
      getScaffold: () => mockScaffold,
      getMatrixService: () => mockMatrixService,
    );
  });

  tearDown(() {
    compose.dispose();
    msgCtrl.dispose();
  });

  group('toggleReaction', () {
    test('returns early when timeline is null', () async {
      final nullTimelineActions = ChatMessageActions(
        getRoomId: () => '!room:example.com',
        getRoom: () => mockRoom,
        getTimeline: () => null,
        compose: compose,
        msgCtrl: msgCtrl,
        getScaffold: () => mockScaffold,
        getMatrixService: () => mockMatrixService,
      );

      await nullTimelineActions.toggleReaction(mockEvent, '👍');

      verifyNever(mockRoom.sendReaction(any, any));
    });

    test('sends reaction when no existing reaction found', () async {
      when(mockEvent.aggregatedEvents(mockTimeline, RelationshipTypes.reaction))
          .thenReturn(<Event>{});
      when(mockRoom.sendReaction(any, any))
          .thenAnswer((_) async => r'$reaction');

      await actions.toggleReaction(mockEvent, '👍');

      verify(mockRoom.sendReaction(r'$event1', '👍')).called(1);
    });

    test('redacts existing reaction', () async {
      final existingReaction = MockEvent();
      when(existingReaction.senderId).thenReturn('@me:example.com');
      when(existingReaction.content).thenReturn({
        'm.relates_to': {'key': '👍'},
      });
      when(existingReaction.redactEvent()).thenAnswer((_) async => r'$redact');

      when(mockEvent.aggregatedEvents(mockTimeline, RelationshipTypes.reaction))
          .thenReturn(<Event>{existingReaction});

      await actions.toggleReaction(mockEvent, '👍');

      verify(existingReaction.redactEvent()).called(1);
      verifyNever(mockRoom.sendReaction(any, any));
    });

    test('shows snackbar on error', () async {
      when(mockEvent.aggregatedEvents(mockTimeline, RelationshipTypes.reaction))
          .thenReturn(<Event>{});
      when(mockRoom.sendReaction(any, any))
          .thenThrow(Exception('network error'));

      await actions.toggleReaction(mockEvent, '👍');

      verify(mockScaffold.showSnackBar(any)).called(1);
    });
  });

  group('togglePin', () {
    test('pins an unpinned message', () async {
      when(mockRoom.pinnedEventIds).thenReturn([]);
      when(mockRoom.setPinnedEvents(any)).thenAnswer((_) async => '');

      await actions.togglePin(mockEvent);

      verify(mockRoom.setPinnedEvents([r'$event1'])).called(1);
    });

    test('unpins a pinned message', () async {
      when(mockRoom.pinnedEventIds).thenReturn([r'$event1']);
      when(mockRoom.setPinnedEvents(any)).thenAnswer((_) async => '');

      await actions.togglePin(mockEvent);

      verify(mockRoom.setPinnedEvents([])).called(1);
    });

    test('shows snackbar on error', () async {
      when(mockRoom.pinnedEventIds).thenReturn([]);
      when(mockRoom.setPinnedEvents(any))
          .thenThrow(Exception('permission denied'));

      await actions.togglePin(mockEvent);

      verify(mockScaffold.showSnackBar(any)).called(1);
    });
  });

  group('send', () {
    test('returns early when text and attachments are both empty', () async {
      msgCtrl.text = '';

      await actions.send();

      verifyNever(mockRoom.sendTextEvent(any));
    });

    test('sends text event and clears compose state', () async {
      msgCtrl.text = 'hello world';
      when(mockRoom.sendTextEvent(
        any,
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
      ),).thenAnswer((_) async => r'$sent');

      await actions.send();

      verify(mockRoom.sendTextEvent(
        'hello world',
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
      ),).called(1);
      expect(msgCtrl.text, isEmpty);
      expect(compose.replyNotifier.value, isNull);
      expect(compose.editNotifier.value, isNull);
    });

    test('sends with inReplyTo when reply is set', () async {
      final replyEvent = MockEvent();
      compose.setReplyTo(replyEvent);
      msgCtrl.text = 'my reply';
      when(mockRoom.sendTextEvent(
        any,
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
      ),).thenAnswer((_) async => r'$sent');

      await actions.send();

      verify(mockRoom.sendTextEvent(
        'my reply',
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
      ),).called(1);
    });

    test('sends with editEventId when edit is set', () async {
      final editEvent = MockEvent();
      when(editEvent.eventId).thenReturn(r'$edit1');
      when(editEvent.body).thenReturn('original');
      when(editEvent.getDisplayEvent(any)).thenReturn(editEvent);
      compose.setEditEvent(editEvent, mockTimeline, msgCtrl);
      msgCtrl.text = 'edited text';
      when(mockRoom.sendTextEvent(
        any,
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
      ),).thenAnswer((_) async => r'$sent');

      await actions.send();

      verify(mockRoom.sendTextEvent(
        'edited text',
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
      ),).called(1);
    });

    test('restores compose state on send error', () async {
      msgCtrl.text = 'will fail';
      final replyEvent = MockEvent();
      compose.setReplyTo(replyEvent);
      when(mockRoom.sendTextEvent(
        any,
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
      ),).thenThrow(Exception('send failed'));

      await actions.send();

      expect(msgCtrl.text, 'will fail');
      expect(compose.replyNotifier.value, replyEvent);
      verify(mockScaffold.showSnackBar(any)).called(1);
    });

    test('returns early when room is null', () async {
      final nullRoomActions = ChatMessageActions(
        getRoomId: () => '!room:example.com',
        getRoom: () => null,
        getTimeline: () => mockTimeline,
        compose: compose,
        msgCtrl: msgCtrl,
        getScaffold: () => mockScaffold,
        getMatrixService: () => mockMatrixService,
      );
      msgCtrl.text = 'hello';

      await nullRoomActions.send();

      verifyNever(mockRoom.sendTextEvent(any));
    });
  });
}

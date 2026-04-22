
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:kohera/features/calling/services/call_signaling_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>()])
import 'call_signaling_service_test.mocks.dart';
import 'call_test_helpers.dart';

void main() {
  late MockClient mockClient;
  late CachedStreamController<Event> timelineController;
  late CallSignalingService service;

  setUp(() {
    mockClient = MockClient();
    timelineController = CachedStreamController<Event>();
    when(mockClient.userID).thenReturn('@alice:example.com');
    when(mockClient.deviceID).thenReturn('DEV1');
    when(mockClient.onTimelineEvent).thenReturn(timelineController);
    service = CallSignalingService(client: mockClient);
    service.startSignalingListener();
  });

  tearDown(() {
    service.dispose();
  });

  MockRoom setupRoom(String roomId, {bool direct = true}) {
    final room = MockRoom();
    when(mockClient.getRoomById(roomId)).thenReturn(room);
    when(room.isDirectChat).thenReturn(direct);
    return room;
  }

  FakeEvent makeInviteEvent({
    String roomId = '!r:x',
    String senderId = '@bob:example.com',
    Room? room,
  }) =>
      FakeEvent(
        type: kCallInvite,
        roomId: roomId,
        senderId: senderId,
        content: const {
          'call_id': 'legacy1',
          'version': 1,
          'offer': {'type': 'offer', 'sdp': ''},
        },
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: room,
        senderFromMemoryOrFallback: FakeUser(displayName: 'Bob'),
      );

  group('legacy m.call.invite handling', () {
    test('emits LegacyCallAttempt for invite from other user in DM', () async {
      const roomId = '!dm:x';
      final room = setupRoom(roomId);
      final events = <SignalingEvent>[];
      final sub = service.events.listen(events.add);

      timelineController.add(makeInviteEvent(roomId: roomId, room: room));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      final ev = events.single as LegacyCallAttempt;
      expect(ev.roomId, roomId);
      expect(ev.senderId, '@bob:example.com');

      await sub.cancel();
    });

    test('ignores invite from self', () async {
      const roomId = '!dm:x';
      final room = setupRoom(roomId);
      final events = <SignalingEvent>[];
      final sub = service.events.listen(events.add);

      timelineController.add(
        makeInviteEvent(
          roomId: roomId,
          senderId: '@alice:example.com',
          room: room,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await sub.cancel();
    });

    test('ignores invite in non-DM room', () async {
      const roomId = '!group:x';
      final room = setupRoom(roomId, direct: false);
      final events = <SignalingEvent>[];
      final sub = service.events.listen(events.add);

      timelineController.add(makeInviteEvent(roomId: roomId, room: room));
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await sub.cancel();
    });

    test('ignores non-invite event types', () async {
      const roomId = '!dm:x';
      final room = setupRoom(roomId);
      final events = <SignalingEvent>[];
      final sub = service.events.listen(events.add);

      timelineController.add(
        FakeEvent(
          type: kCallHangup,
          roomId: roomId,
          senderId: '@bob:example.com',
          content: const {'call_id': 'x'},
          originServerTs: DateTime.now().millisecondsSinceEpoch,
          room: room,
          senderFromMemoryOrFallback: FakeUser(displayName: 'Bob'),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await sub.cancel();
    });
  });

  group('lifecycle', () {
    test('stopSignalingListener halts events', () async {
      const roomId = '!dm:x';
      final room = setupRoom(roomId);
      final events = <SignalingEvent>[];
      final sub = service.events.listen(events.add);

      service.stopSignalingListener();
      timelineController.add(makeInviteEvent(roomId: roomId, room: room));
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await sub.cancel();
    });
  });
}

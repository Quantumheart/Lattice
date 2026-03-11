import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/features/calling/models/call_constants.dart';
import 'package:lattice/features/calling/services/call_signaling_service.dart';
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
  });

  tearDown(() {
    service.dispose();
  });

  MockRoom _setupRoom(String roomId, {bool direct = true, bool encrypted = false}) {
    final room = MockRoom();
    when(mockClient.getRoomById(roomId)).thenReturn(room);
    when(room.isDirectChat).thenReturn(direct);
    when(room.encrypted).thenReturn(encrypted);
    when(room.sendEvent(any, type: anyNamed('type')))
        .thenAnswer((_) async => 'ev1');
    return room;
  }

  FakeEvent _makeInviteEvent({
    String callId = 'call1',
    String roomId = '!r:x',
    String senderId = '@bob:example.com',
    int? originServerTs,
    int lifetime = 60000,
    bool isVideo = false,
    Room? room,
  }) {
    final now = originServerTs ?? DateTime.now().millisecondsSinceEpoch;
    return FakeEvent(
      type: kCallInvite,
      roomId: roomId,
      senderId: senderId,
      content: {
        'call_id': callId,
        'version': 1,
        'lifetime': lifetime,
        'offer': {'type': 'offer', 'sdp': ''},
        'is_video': isVideo,
      },
      originServerTs: now,
      room: room,
      senderFromMemoryOrFallback: FakeUser(displayName: 'Bob'),
    );
  }

  // ── generateCallId ──────────────────────────────────────────

  group('generateCallId', () {
    test('returns non-empty string', () {
      expect(service.generateCallId(), isNotEmpty);
    });

    test('unique across 100 calls', () {
      final ids = List.generate(100, (_) => service.generateCallId());
      expect(ids.toSet().length, 100);
    });
  });

  // ── sendCallInvite ──────────────────────────────────────────

  group('sendCallInvite', () {
    test('sends correct type and content', () async {
      final room = _setupRoom('!r:x');

      await service.sendCallInvite('!r:x', 'c1');

      final captured = verify(room.sendEvent(
        captureAny,
        type: captureAnyNamed('type'),
      )).captured;
      final content = captured[0] as Map<String, dynamic>;
      final type = captured[1] as String;
      expect(type, kCallInvite);
      expect(content['call_id'], 'c1');
      expect(content['version'], 1);
      expect(content['lifetime'], 60000);
      expect(content['is_video'], false);
    });

    test('null room returns early', () async {
      when(mockClient.getRoomById('!r:x')).thenReturn(null);
      await service.sendCallInvite('!r:x', 'c1');
    });

    test('isVideo flag', () async {
      final room = _setupRoom('!r:x');

      await service.sendCallInvite('!r:x', 'c1', isVideo: true);

      final captured = verify(room.sendEvent(
        captureAny,
        type: anyNamed('type'),
      )).captured;
      expect((captured[0] as Map)['is_video'], true);
    });

    test('prepares encryption for encrypted room', () async {
      final room = _setupRoom('!r:x', encrypted: true);
      when(room.encrypted).thenReturn(true);

      await service.sendCallInvite('!r:x', 'c1');

      verify(room.sendEvent(any, type: anyNamed('type'))).called(1);
    });
  });

  // ── sendCallAnswer ──────────────────────────────────────────

  group('sendCallAnswer', () {
    test('sends correct type and content', () async {
      final room = _setupRoom('!r:x');

      await service.sendCallAnswer('!r:x', 'c1');

      final captured = verify(room.sendEvent(
        captureAny,
        type: captureAnyNamed('type'),
      )).captured;
      expect(captured[1], kCallAnswer);
      expect((captured[0] as Map)['call_id'], 'c1');
    });

    test('null room returns early', () async {
      when(mockClient.getRoomById('!r:x')).thenReturn(null);
      await service.sendCallAnswer('!r:x', 'c1');
    });
  });

  // ── sendCallReject ──────────────────────────────────────────

  group('sendCallReject', () {
    test('sends correct type and content', () async {
      final room = _setupRoom('!r:x');

      await service.sendCallReject('!r:x', 'c1');

      final captured = verify(room.sendEvent(
        captureAny,
        type: captureAnyNamed('type'),
      )).captured;
      expect(captured[1], kCallReject);
      expect((captured[0] as Map)['call_id'], 'c1');
    });

    test('null room returns early', () async {
      when(mockClient.getRoomById('!r:x')).thenReturn(null);
      await service.sendCallReject('!r:x', 'c1');
    });
  });

  // ── sendCallHangup ──────────────────────────────────────────

  group('sendCallHangup', () {
    test('sends correct type and content', () async {
      final room = _setupRoom('!r:x');

      await service.sendCallHangup('!r:x', 'c1');

      final captured = verify(room.sendEvent(
        captureAny,
        type: captureAnyNamed('type'),
      )).captured;
      expect(captured[1], kCallHangup);
      final content = captured[0] as Map;
      expect(content['call_id'], 'c1');
      expect(content['reason'], kHangupUserHangup);
    });

    test('custom reason', () async {
      final room = _setupRoom('!r:x');

      await service.sendCallHangup('!r:x', 'c1', reason: 'glare');

      final captured = verify(room.sendEvent(
        captureAny,
        type: anyNamed('type'),
      )).captured;
      expect((captured[0] as Map)['reason'], 'glare');
    });

    test('null room returns early', () async {
      when(mockClient.getRoomById('!r:x')).thenReturn(null);
      await service.sendCallHangup('!r:x', 'c1');
    });
  });

  // ── listener lifecycle ──────────────────────────────────────

  group('listener lifecycle', () {
    test('subscribes on start', () {
      service.startSignalingListener(
        getActiveCallId: () => null,
        getCallState: () => 'idle',
      );
      expect(timelineController.stream.isBroadcast, true);
    });

    test('cancels on stop', () {
      service.startSignalingListener(
        getActiveCallId: () => null,
        getCallState: () => 'idle',
      );
      service.stopSignalingListener();
    });
  });

  // ── event filtering ─────────────────────────────────────────

  group('event filtering', () {
    late MockRoom mockRoom;

    setUp(() {
      mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => null,
        getCallState: () => 'idle',
      );
    });

    test('ignores non-call types', () async {
      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: 'm.room.message',
        roomId: '!r:x',
        senderId: '@bob:example.com',
        content: {},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('ignores null roomId', () async {
      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallInvite,
        roomId: null,
        senderId: '@bob:example.com',
        content: {'call_id': 'c1'},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('ignores non-direct rooms', () async {
      final nonDirectRoom = MockRoom();
      when(nonDirectRoom.isDirectChat).thenReturn(false);
      when(mockClient.getRoomById('!nd:x')).thenReturn(nonDirectRoom);

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallInvite,
        roomId: '!nd:x',
        senderId: '@bob:example.com',
        content: {'call_id': 'c1'},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: nonDirectRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('ignores own events', () async {
      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallInvite,
        roomId: '!r:x',
        senderId: '@alice:example.com',
        content: {'call_id': 'c1'},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });

  // ── incoming invite (idle) ──────────────────────────────────

  group('incoming invite (idle)', () {
    late MockRoom mockRoom;

    setUp(() {
      mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => null,
        getCallState: () => 'idle',
      );
    });

    test('emits IncomingInvite', () async {
      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(_makeInviteEvent(room: mockRoom));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first, isA<IncomingInvite>());
    });

    test('parses fields correctly', () async {
      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(_makeInviteEvent(
        callId: 'test-call',
        isVideo: true,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      final invite = events.first as IncomingInvite;
      expect(invite.callId, 'test-call');
      expect(invite.info.roomId, '!r:x');
      expect(invite.info.isVideo, true);
      expect(invite.info.callerName, 'Bob');
    });
  });

  // ── incoming invite (non-idle) ──────────────────────────────

  group('incoming invite (non-idle)', () {
    test('ignored when connected', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'c1',
        getCallState: () => 'connected',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(_makeInviteEvent(room: mockRoom));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('ignored when joining', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'c1',
        getCallState: () => 'joining',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(_makeInviteEvent(room: mockRoom));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });

  // ── stale invite ────────────────────────────────────────────

  group('stale invite', () {
    test('ignored when lifetime expired', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => null,
        getCallState: () => 'idle',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      final staleTs = DateTime.now().millisecondsSinceEpoch - 120000;
      timelineController.add(_makeInviteEvent(
        originServerTs: staleTs,
        lifetime: 60000,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });

  // ── missing call_id ─────────────────────────────────────────

  group('missing call_id', () {
    test('no event emitted', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => null,
        getCallState: () => 'idle',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallInvite,
        roomId: '!r:x',
        senderId: '@bob:example.com',
        content: {'version': 1, 'lifetime': 60000},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
        senderFromMemoryOrFallback: FakeUser(displayName: 'Bob'),
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });

  // ── glare resolution ────────────────────────────────────────

  group('glare resolution', () {
    test('local wins (lower userId) → ignored', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'my-call',
        getCallState: () => 'ringingOutgoing',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(_makeInviteEvent(
        senderId: '@zara:example.com',
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('remote wins → GlareResolved + hangup sent', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'my-call',
        getCallState: () => 'ringingOutgoing',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(_makeInviteEvent(
        senderId: '@aaa:example.com',
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first, isA<GlareResolved>());
      final glare = events.first as GlareResolved;
      expect(glare.myCallId, 'my-call');

      verify(mockRoom.sendEvent(
        argThat(containsPair('reason', 'glare')),
        type: kCallHangup,
      )).called(1);
    });

    test('null myCallId handled (no hangup sent)', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => null,
        getCallState: () => 'ringingOutgoing',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(_makeInviteEvent(
        senderId: '@aaa:example.com',
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      final glare = events.first as GlareResolved;
      expect(glare.myCallId, isNull);

      verifyNever(mockRoom.sendEvent(
        argThat(containsPair('reason', 'glare')),
        type: kCallHangup,
      ));
    });
  });

  // ── answer handling ─────────────────────────────────────────

  group('answer handling', () {
    test('emits AnswerReceived when id matches + ringingOutgoing', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'c1',
        getCallState: () => 'ringingOutgoing',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallAnswer,
        roomId: '!r:x',
        senderId: '@bob:example.com',
        content: {'call_id': 'c1', 'version': 1},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first, isA<AnswerReceived>());
      expect((events.first as AnswerReceived).callId, 'c1');
    });

    test('ignored when call id does not match', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'c1',
        getCallState: () => 'ringingOutgoing',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallAnswer,
        roomId: '!r:x',
        senderId: '@bob:example.com',
        content: {'call_id': 'wrong', 'version': 1},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('ignored when not ringingOutgoing', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'c1',
        getCallState: () => 'connected',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallAnswer,
        roomId: '!r:x',
        senderId: '@bob:example.com',
        content: {'call_id': 'c1', 'version': 1},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });

  // ── reject handling ─────────────────────────────────────────

  group('reject handling', () {
    test('emits RejectReceived when id matches + ringingOutgoing', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'c1',
        getCallState: () => 'ringingOutgoing',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallReject,
        roomId: '!r:x',
        senderId: '@bob:example.com',
        content: {'call_id': 'c1', 'version': 1},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first, isA<RejectReceived>());
    });

    test('ignored when not ringingOutgoing', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'c1',
        getCallState: () => 'idle',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallReject,
        roomId: '!r:x',
        senderId: '@bob:example.com',
        content: {'call_id': 'c1', 'version': 1},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });

  // ── hangup handling ─────────────────────────────────────────

  group('hangup handling', () {
    test('emits HangupReceived when id matches (any state)', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'c1',
        getCallState: () => 'connected',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallHangup,
        roomId: '!r:x',
        senderId: '@bob:example.com',
        content: {'call_id': 'c1', 'version': 1},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.first, isA<HangupReceived>());
    });

    test('ignored when call id does not match', () async {
      final mockRoom = _setupRoom('!r:x');
      service.startSignalingListener(
        getActiveCallId: () => 'c1',
        getCallState: () => 'connected',
      );

      final events = <SignalingEvent>[];
      service.events.listen(events.add);

      timelineController.add(FakeEvent(
        type: kCallHangup,
        roomId: '!r:x',
        senderId: '@bob:example.com',
        content: {'call_id': 'wrong', 'version': 1},
        originServerTs: DateTime.now().millisecondsSinceEpoch,
        room: mockRoom,
      ));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });
}

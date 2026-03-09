import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/core/services/call_service.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/voip/models/voip_id.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<VoIP>(),
  MockSpec<GroupCallSession>(),
])
import 'call_service_test.mocks.dart';

// ── LiveKit Mocks ─────────────────────────────────────────

class _MockLocalParticipant extends Fake
    implements livekit.LocalParticipant {
  bool micEnabled = false;
  bool cameraEnabled = false;
  bool screenShareEnabled = false;
  bool throwOnToggle = false;

  @override
  Future<livekit.LocalTrackPublication?> setMicrophoneEnabled(
    bool enabled, {
    livekit.AudioCaptureOptions? audioCaptureOptions,
  }) async {
    if (throwOnToggle) throw Exception('mic error');
    micEnabled = enabled;
    return null;
  }

  @override
  Future<livekit.LocalTrackPublication?> setCameraEnabled(
    bool enabled, {
    livekit.CameraCaptureOptions? cameraCaptureOptions,
  }) async {
    if (throwOnToggle) throw Exception('camera error');
    cameraEnabled = enabled;
    return null;
  }

  @override
  Future<livekit.LocalTrackPublication?> setScreenShareEnabled(
    bool enabled, {
    bool? captureScreenAudio,
    livekit.ScreenShareCaptureOptions? screenShareCaptureOptions,
  }) async {
    if (throwOnToggle) throw Exception('screenshare error');
    screenShareEnabled = enabled;
    return null;
  }
}

class _FakeEventsListener<T> extends Fake
    implements livekit.EventsListener<T> {
  final _handlers = <Type, List<Function>>{};

  @override
  livekit.CancelListenFunc on<E>(
    FutureOr<void> Function(E) then, {
    bool Function(E)? filter,
  }) {
    _handlers.putIfAbsent(E, () => []).add(then);
    return () async {};
  }

  @override
  Future<bool> dispose() async {
    _handlers.clear();
    return true;
  }

  void fire<E>(E event) {
    final handlers = _handlers[E];
    if (handlers != null) {
      for (final handler in handlers) {
        (handler as void Function(E))(event);
      }
    }
  }
}

class _FakeLiveKitRoom extends Fake implements livekit.Room {
  _MockLocalParticipant? _localParticipant;
  final Map<String, livekit.RemoteParticipant> _remoteParticipants = {};
  _FakeEventsListener<livekit.RoomEvent>? _listener;
  bool connected = false;
  bool disconnected = false;
  bool disposed = false;
  bool throwOnConnect = false;

  @override
  livekit.LocalParticipant? get localParticipant => _localParticipant;

  @override
  UnmodifiableMapView<String, livekit.RemoteParticipant>
      get remoteParticipants =>
          UnmodifiableMapView(_remoteParticipants);

  @override
  livekit.EventsListener<livekit.RoomEvent> createListener({
    bool synchronized = false,
  }) {
    _listener = _FakeEventsListener<livekit.RoomEvent>();
    return _listener!;
  }

  @override
  Future<void> connect(
    String url,
    String token, {
    livekit.ConnectOptions? connectOptions,
    livekit.RoomOptions? roomOptions,
    livekit.FastConnectOptions? fastConnectOptions,
  }) async {
    if (throwOnConnect) throw Exception('connect failed');
    connected = true;
    _localParticipant = _MockLocalParticipant();
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Future<bool> dispose() async {
    disposed = true;
    return true;
  }
}

void main() {
  late MockClient mockClient;
  late CallService service;
  late MockVoIP mockVoip;

  setUp(() {
    mockClient = MockClient();
    mockVoip = MockVoIP();
    when(mockClient.rooms).thenReturn([]);
    service = CallService(client: mockClient);
  });

  void injectVoip() {
    service.voipForTest = mockVoip;
  }

  _FakeLiveKitRoom setupLiveKitMocks() {
    final fakeRoom = _FakeLiveKitRoom();
    service.roomFactoryForTest = () => fakeRoom;

    when(mockClient.userID).thenReturn('@user:example.com');
    when(mockClient.deviceID).thenReturn('DEVICE1');
    when(mockClient.requestOpenIdToken(any, any)).thenAnswer(
      (_) async => OpenIdCredentials(
        accessToken: 'openid_token',
        expiresIn: 3600,
        matrixServerName: 'example.com',
        tokenType: 'Bearer',
      ),
    );

    service.httpPostForTest = (url, {headers, body}) async {
      return http.Response(
        jsonEncode({'url': 'wss://lk.example.com', 'token': 'lk_token'}),
        200,
      );
    };

    return fakeRoom;
  }

  ({MockGroupCallSession groupCall, CachedStreamController<MatrixRTCCallEvent> events}) setupGroupCall(MockRoom mockRoom) {
    final mockGroupCall = MockGroupCallSession();
    final eventStreamController =
        CachedStreamController<MatrixRTCCallEvent>();

    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.activeGroupCallIds(mockVoip)).thenReturn(['call_1']);
    when(mockRoom.getCallMembershipsFromRoom(mockVoip)).thenReturn({});
    when(mockGroupCall.room).thenReturn(mockRoom);
    when(mockGroupCall.groupCallId).thenReturn('call_1');
    final voipId = VoipId(roomId: '!room:example.com', callId: 'call_1');
    when(mockVoip.groupCalls).thenReturn({voipId: mockGroupCall});
    when(mockGroupCall.matrixRTCEventStream).thenReturn(eventStreamController);
    when(mockGroupCall.enter()).thenAnswer((_) async {});
    when(mockGroupCall.leave()).thenAnswer((_) async {});

    return (groupCall: mockGroupCall, events: eventStreamController);
  }

  group('CallService initial state', () {
    test('callState starts as idle', () {
      expect(service.callState, LatticeCallState.idle);
    });

    test('activeGroupCall starts as null', () {
      expect(service.activeGroupCall, isNull);
    });

    test('activeCallRoomId starts as null', () {
      expect(service.activeCallRoomId, isNull);
    });

    test('voip starts as null before init', () {
      expect(service.voip, isNull);
    });

    test('LiveKit state starts with defaults', () {
      expect(service.livekitRoom, isNull);
      expect(service.participants, isEmpty);
      expect(service.isMicEnabled, isFalse);
      expect(service.isCameraEnabled, isFalse);
      expect(service.isScreenShareEnabled, isFalse);
      expect(service.activeSpeakers, isEmpty);
    });
  });

  group('roomHasActiveCall', () {
    test('returns false when voip is null', () {
      expect(service.roomHasActiveCall('!room:example.com'), isFalse);
    });

    test('returns false for unknown room', () {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.roomHasActiveCall('!room:example.com'), isFalse);
    });
  });

  group('activeCallIdsForRoom', () {
    test('returns empty when voip is null', () {
      expect(service.activeCallIdsForRoom('!room:example.com'), isEmpty);
    });

    test('returns empty for unknown room', () {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.activeCallIdsForRoom('!room:example.com'), isEmpty);
    });
  });

  group('callParticipantCount', () {
    test('returns 0 when voip is null', () {
      expect(service.callParticipantCount('!room:example.com', 'call1'), 0);
    });

    test('returns 0 for unknown room', () {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.callParticipantCount('!room:example.com', 'call1'), 0);
    });
  });

  group('callMembershipsForRoom', () {
    test('returns empty when voip is null', () {
      expect(service.callMembershipsForRoom('!room:example.com'), isEmpty);
    });

    test('returns empty for unknown room', () {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.callMembershipsForRoom('!room:example.com'), isEmpty);
    });
  });

  group('joinCall', () {
    test('does nothing when voip is null', () async {
      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.idle);
    });

    test('returns early when room not found', () async {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);

      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.idle);
    });

    test('transitions to failed when enter throws', () async {
      final mockRoom = MockRoom();

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.activeGroupCallIds(mockVoip)).thenReturn([]);
      when(mockRoom.getCallMembershipsFromRoom(mockVoip)).thenReturn({});
      when(mockVoip.groupCalls).thenReturn({});

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.failed);
      expect(service.activeGroupCall, isNull);
    });

    test('notifies listeners on joining transition', () async {
      final mockRoom = MockRoom();

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.activeGroupCallIds(mockVoip)).thenReturn([]);
      when(mockRoom.getCallMembershipsFromRoom(mockVoip)).thenReturn({});
      when(mockVoip.groupCalls).thenReturn({});

      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      await service.joinCall('!room:example.com');

      expect(states, contains(LatticeCallState.joining));
    });

    test('connects to LiveKit when backend is LiveKitBackend', () async {
      final mockRoom = MockRoom();
      final fakeRoom = setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      final livekitBackend = LiveKitBackend(
        livekitServiceUrl: 'https://lk-jwt.example.com/token',
        livekitAlias: '#room:example.com',
      );

      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.connected);
      expect(fakeRoom.connected, isTrue);
      expect(service.livekitRoom, same(fakeRoom));
      expect(service.isMicEnabled, isFalse);
      expect(service.isCameraEnabled, isFalse);
      expect(service.isScreenShareEnabled, isFalse);

      verify(result.groupCall.enter()).called(1);
    });

    test('transitions to failed when token exchange throws', () async {
      final mockRoom = MockRoom();
      setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockClient.requestOpenIdToken(any, any))
          .thenThrow(Exception('token error'));

      final livekitBackend = LiveKitBackend(
        livekitServiceUrl: 'https://lk-jwt.example.com/token',
        livekitAlias: '#room:example.com',
      );

      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.failed);
      expect(service.activeGroupCall, isNull);
      expect(service.livekitRoom, isNull);
    });

    test('transitions to failed when LiveKit connect throws', () async {
      final mockRoom = MockRoom();
      final fakeRoom = setupLiveKitMocks();
      setupGroupCall(mockRoom);
      fakeRoom.throwOnConnect = true;

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      final livekitBackend = LiveKitBackend(
        livekitServiceUrl: 'https://lk-jwt.example.com/token',
        livekitAlias: '#room:example.com',
      );

      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.failed);
      expect(service.livekitRoom, isNull);
    });

    test('transitions to failed when token response is not 200', () async {
      final mockRoom = MockRoom();
      setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      service.httpPostForTest = (url, {headers, body}) async {
        return http.Response('Unauthorized', 401);
      };

      final livekitBackend = LiveKitBackend(
        livekitServiceUrl: 'https://lk-jwt.example.com/token',
        livekitAlias: '#room:example.com',
      );

      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.failed);
    });
  });

  group('leaveCall', () {
    test('does nothing when no active call', () async {
      await service.leaveCall();
      expect(service.callState, LatticeCallState.idle);
    });

    test('does not notify when no active call', () async {
      var notified = false;
      service.addListener(() => notified = true);

      await service.leaveCall();
      expect(notified, isFalse);
    });

    test('disconnects LiveKit and transitions through disconnecting', () async {
      final mockRoom = MockRoom();
      final fakeRoom = setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      final livekitBackend = LiveKitBackend(
        livekitServiceUrl: 'https://lk-jwt.example.com/token',
        livekitAlias: '#room:example.com',
      );

      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      await service.leaveCall();

      expect(states, contains(LatticeCallState.disconnecting));
      expect(states.last, LatticeCallState.idle);
      expect(fakeRoom.disconnected, isTrue);
      expect(fakeRoom.disposed, isTrue);
      expect(service.livekitRoom, isNull);
      expect(service.participants, isEmpty);
      expect(service.isMicEnabled, isFalse);
    });
  });

  group('LiveKit reconnection events', () {
    late _FakeLiveKitRoom fakeRoom;
    late MockGroupCallSession mockGroupCall;

    setUp(() async {
      final mockRoom = MockRoom();
      fakeRoom = setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);
      mockGroupCall = result.groupCall;

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );
    });

    test('RoomReconnectingEvent sets state to reconnecting', () {
      fakeRoom._listener!.fire(const livekit.RoomReconnectingEvent());
      expect(service.callState, LatticeCallState.reconnecting);
    });

    test('RoomReconnectedEvent sets state to connected', () {
      fakeRoom._listener!.fire(const livekit.RoomReconnectingEvent());
      fakeRoom._listener!.fire(const livekit.RoomReconnectedEvent());
      expect(service.callState, LatticeCallState.connected);
    });

    test('RoomDisconnectedEvent cleans up and sets state to failed', () {
      fakeRoom._listener!.fire(livekit.RoomDisconnectedEvent());

      expect(service.callState, LatticeCallState.failed);
      expect(service.livekitRoom, isNull);
      expect(service.participants, isEmpty);
      expect(service.activeGroupCall, isNull);
    });

    test('RoomDisconnectedEvent leaves the Matrix group call', () async {
      fakeRoom._listener!.fire(livekit.RoomDisconnectedEvent());
      await Future<void>.delayed(Duration.zero);

      verify(mockGroupCall.leave()).called(1);
    });
  });

  group('MatrixRTC events clean up LiveKit', () {
    late _FakeLiveKitRoom fakeRoom;
    late CachedStreamController<MatrixRTCCallEvent> eventStream;

    setUp(() async {
      final mockRoom = MockRoom();
      fakeRoom = setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);
      eventStream = result.events;

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );
    });

    test('GroupCallStateChanged ended cleans up LiveKit', () async {
      expect(service.livekitRoom, isNotNull);

      eventStream.add(GroupCallStateChanged(GroupCallState.ended));
      await Future<void>.delayed(Duration.zero);

      expect(service.callState, LatticeCallState.idle);
      expect(service.livekitRoom, isNull);
      expect(service.activeGroupCall, isNull);
      expect(fakeRoom.disposed, isTrue);
    });
  });

  group('concurrent join guard', () {
    test('second joinCall is rejected while first is in progress', () async {
      final mockRoom = MockRoom();
      setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      final livekitBackend = LiveKitBackend(
        livekitServiceUrl: 'https://lk-jwt.example.com/token',
        livekitAlias: '#room:example.com',
      );

      final first = service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      await first;
      expect(service.callState, LatticeCallState.connected);
    });
  });

  group('LiveKit participant sync', () {
    late _FakeLiveKitRoom fakeRoom;

    setUp(() async {
      final mockRoom = MockRoom();
      fakeRoom = setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );
    });

    test('participants list is empty initially', () {
      expect(service.participants, isEmpty);
    });

    test('ParticipantConnectedEvent syncs participants', () {
      final fakeRemote = _FakeRemoteParticipant();
      fakeRoom._remoteParticipants['user2'] = fakeRemote;

      fakeRoom._listener!.fire(
        livekit.ParticipantConnectedEvent(participant: fakeRemote),
      );

      expect(service.participants, hasLength(1));
    });

    test('ParticipantDisconnectedEvent syncs participants', () {
      final fakeRemote = _FakeRemoteParticipant();
      fakeRoom._remoteParticipants['user2'] = fakeRemote;

      fakeRoom._listener!.fire(
        livekit.ParticipantConnectedEvent(participant: fakeRemote),
      );
      expect(service.participants, hasLength(1));

      fakeRoom._remoteParticipants.remove('user2');
      fakeRoom._listener!.fire(
        livekit.ParticipantDisconnectedEvent(participant: fakeRemote),
      );
      expect(service.participants, isEmpty);
    });

    test('ActiveSpeakersChangedEvent updates active speakers', () {
      fakeRoom._listener!.fire(
        const livekit.ActiveSpeakersChangedEvent(speakers: []),
      );
      expect(service.activeSpeakers, isEmpty);
    });
  });

  group('Track toggles', () {
    late _FakeLiveKitRoom fakeRoom;

    setUp(() async {
      final mockRoom = MockRoom();
      fakeRoom = setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );
    });

    test('toggleMicrophone enables and disables mic', () async {
      await service.toggleMicrophone();
      expect(service.isMicEnabled, isTrue);
      expect(fakeRoom._localParticipant!.micEnabled, isTrue);

      await service.toggleMicrophone();
      expect(service.isMicEnabled, isFalse);
      expect(fakeRoom._localParticipant!.micEnabled, isFalse);
    });

    test('toggleCamera enables and disables camera', () async {
      await service.toggleCamera();
      expect(service.isCameraEnabled, isTrue);
      expect(fakeRoom._localParticipant!.cameraEnabled, isTrue);

      await service.toggleCamera();
      expect(service.isCameraEnabled, isFalse);
      expect(fakeRoom._localParticipant!.cameraEnabled, isFalse);
    });

    test('toggleScreenShare enables and disables screen share', () async {
      await service.toggleScreenShare();
      expect(service.isScreenShareEnabled, isTrue);
      expect(fakeRoom._localParticipant!.screenShareEnabled, isTrue);

      await service.toggleScreenShare();
      expect(service.isScreenShareEnabled, isFalse);
      expect(fakeRoom._localParticipant!.screenShareEnabled, isFalse);
    });

    test('toggleMicrophone reverts on error', () async {
      fakeRoom._localParticipant!.throwOnToggle = true;

      await service.toggleMicrophone();
      expect(service.isMicEnabled, isFalse);
    });

    test('toggleCamera reverts on error', () async {
      fakeRoom._localParticipant!.throwOnToggle = true;

      await service.toggleCamera();
      expect(service.isCameraEnabled, isFalse);
    });

    test('toggleScreenShare reverts on error', () async {
      fakeRoom._localParticipant!.throwOnToggle = true;

      await service.toggleScreenShare();
      expect(service.isScreenShareEnabled, isFalse);
    });

    test('toggle does nothing when no local participant', () async {
      final noLkService = CallService(client: mockClient);
      await noLkService.toggleMicrophone();
      expect(noLkService.isMicEnabled, isFalse);
    });
  });

  group('fetchTurnServers', () {
    test('returns null on error', () async {
      when(mockClient.getTurnServer()).thenThrow(Exception('no server'));
      final result = await service.fetchTurnServers();
      expect(result, isNull);
    });
  });

  group('updateClient', () {
    test('resets state when client changes', () {
      injectVoip();
      final newClient = MockClient();
      when(newClient.rooms).thenReturn([]);

      service.updateClient(newClient);

      expect(service.voip, isNull);
      expect(service.callState, LatticeCallState.idle);
      expect(service.activeGroupCall, isNull);
      expect(service.client, same(newClient));
    });

    test('does nothing when same client', () {
      injectVoip();
      service.updateClient(mockClient);
      expect(service.voip, same(mockVoip));
    });

    test('cleans up LiveKit on client change', () async {
      final mockRoom = MockRoom();
      final fakeRoom = setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );

      expect(service.livekitRoom, isNotNull);

      final newClient = MockClient();
      when(newClient.rooms).thenReturn([]);
      service.updateClient(newClient);
      await Future<void>.delayed(Duration.zero);

      expect(service.livekitRoom, isNull);
      expect(fakeRoom.disposed, isTrue);
    });
  });

  group('ringing states', () {
    test('initiateCall transitions to ringingOutgoing', () async {
      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(null);

      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      await service.initiateCall('!room:example.com');

      expect(states.first, LatticeCallState.ringingOutgoing);
    });

    test('initiateCall with no room stays in ringingOutgoing briefly', () async {
      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(null);

      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      await service.initiateCall('!room:example.com');
      expect(states.first, LatticeCallState.ringingOutgoing);
    });

    test('cancelOutgoingCall does nothing when not ringing', () async {
      injectVoip();

      service.cancelOutgoingCall();
      expect(service.callState, LatticeCallState.idle);
    });

    test('acceptCall transitions from ringingIncoming to joining', () {
      injectVoip();

      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      service.acceptCall();
      expect(states, isEmpty);
    });

    test('declineCall from ringingIncoming resets to idle', () {
      injectVoip();

      service.declineCall();
      expect(service.callState, LatticeCallState.idle);
    });

    test('callElapsed returns null when not connected', () {
      expect(service.callElapsed, isNull);
    });

    test('incomingCallStream emits events', () async {
      final events = <Object>[];
      service.incomingCallStream.listen(events.add);

      expect(events, isEmpty);
    });
  });

  group('dispose', () {
    test('resets call state', () {
      injectVoip();
      service.dispose();
      expect(service.callState, LatticeCallState.idle);
      expect(service.activeGroupCall, isNull);
      expect(service.voip, isNull);
    });

    test('cleans up LiveKit resources', () async {
      final mockRoom = MockRoom();
      final fakeRoom = setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );

      service.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(fakeRoom.disposed, isTrue);
    });
  });
}

// ── Fake RemoteParticipant ─────────────────────────────────

class _FakeRemoteParticipant extends Fake
    implements livekit.RemoteParticipant {}

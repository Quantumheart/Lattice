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
  MockSpec<CallSession>(),
  MockSpec<User>(),
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
  List<livekit.LocalTrackPublication<livekit.LocalVideoTrack>>
      get videoTrackPublications => [];

  @override
  String get identity => 'local';

  @override
  String get name => 'Local User';

  @override
  bool get isMuted => false;

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
    when(mockRoom.states).thenReturn({});
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

    test('stays idle when room not found from idle state', () async {
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

    test('initiateCall with no room transitions to failed', () async {
      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(null);

      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      await service.initiateCall('!room:example.com');
      expect(states.first, LatticeCallState.ringingOutgoing);
      expect(states.last, LatticeCallState.failed);
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

  // ── Bug-Fix Regression Tests ─────────────────────────────

  group('handleCallEnded guard during joining', () {
    test('handleCallEnded is ignored while _joining is true', () async {
      final mockRoom = MockRoom();
      setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      final enterCompleter = Completer<void>();
      when(result.groupCall.enter()).thenAnswer((_) => enterCompleter.future);

      final joinFuture = service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.isJoining, isTrue);

      service.simulateCallEnded();

      expect(
        service.callState,
        isNot(LatticeCallState.idle),
        reason: 'handleCallEnded must be ignored while _joining is true',
      );

      enterCompleter.complete();
      await joinFuture;

      expect(service.callState, LatticeCallState.connected);
    });

    test('handleCallEnded fires normally when not joining', () {
      final mockRoom = MockRoom();
      final mockCallSession = MockCallSession();
      final mockUser = MockUser();

      injectVoip();
      when(mockCallSession.room).thenReturn(mockRoom);
      when(mockCallSession.remoteUserId).thenReturn('@caller:example.com');
      when(mockCallSession.type).thenReturn(CallType.kVoice);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.states).thenReturn({});
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any)).thenReturn(mockUser);
      when(mockUser.calcDisplayname()).thenReturn('Caller');

      service.simulateIncomingCall(mockCallSession);
      expect(service.callState, LatticeCallState.ringingIncoming);

      service.simulateCallEnded();
      expect(service.callState, LatticeCallState.idle);
    });
  });

  group('MatrixRTC ended event guard during joining', () {
    test('GroupCallStateChanged.ended is ignored while joining', () async {
      final mockRoom = MockRoom();
      setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      final enterCompleter = Completer<void>();
      when(result.groupCall.enter()).thenAnswer((_) => enterCompleter.future);

      final joinFuture = service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.isJoining, isTrue);

      result.events.add(GroupCallStateChanged(GroupCallState.ended));
      await Future<void>.delayed(Duration.zero);

      expect(
        service.callState,
        isNot(LatticeCallState.idle),
        reason: 'ended event must be ignored while _joining is true',
      );

      expect(service.activeGroupCall, isNotNull);

      enterCompleter.complete();
      await joinFuture;

      expect(service.callState, LatticeCallState.connected);
    });

    test('GroupCallStateChanged.ended works normally after connected', () async {
      final mockRoom = MockRoom();
      final fakeRoom = setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);

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
      expect(service.callState, LatticeCallState.connected);

      result.events.add(GroupCallStateChanged(GroupCallState.ended));
      await Future<void>.delayed(Duration.zero);

      expect(service.callState, LatticeCallState.idle);
      expect(service.activeGroupCall, isNull);
      expect(fakeRoom.disposed, isTrue);
    });
  });

  group('joinCall failure cleans up group call membership', () {
    test('groupCall.leave() is called when LiveKit connect fails', () async {
      final mockRoom = MockRoom();
      final fakeRoom = setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);
      fakeRoom.throwOnConnect = true;

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

      expect(service.callState, LatticeCallState.failed);
      verify(result.groupCall.enter()).called(1);
      verify(result.groupCall.leave()).called(1);
    });

    test('groupCall.leave() is called when token exchange fails', () async {
      final mockRoom = MockRoom();
      setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockClient.requestOpenIdToken(any, any))
          .thenThrow(Exception('token error'));

      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.failed);
      verify(result.groupCall.leave()).called(1);
    });

    test('leave() error in catch block is handled gracefully', () async {
      final mockRoom = MockRoom();
      final fakeRoom = setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);
      fakeRoom.throwOnConnect = true;
      when(result.groupCall.leave()).thenThrow(Exception('leave error'));

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

      expect(service.callState, LatticeCallState.failed);
      expect(service.activeGroupCall, isNull);
    });
  });

  // ── End-to-End Call Lifecycle Tests ──────────────────────

  group('E2E: outgoing call lifecycle (caller)', () {
    late MockRoom mockRoom;
    late _FakeLiveKitRoom fakeRoom;
    late MockGroupCallSession mockGroupCall;
    late CachedStreamController<MatrixRTCCallEvent> eventStream;

    final livekitBackend = LiveKitBackend(
      livekitServiceUrl: 'https://lk-jwt.example.com/token',
      livekitAlias: '#room:example.com',
    );

    setUp(() {
      mockRoom = MockRoom();
      fakeRoom = setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);
      mockGroupCall = result.groupCall;
      eventStream = result.events;

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    });

    test('full lifecycle: join → connect → leave', () async {
      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.connected);
      expect(states, contains(LatticeCallState.joining));
      expect(states.last, LatticeCallState.connected);
      expect(service.activeGroupCall, same(mockGroupCall));
      expect(service.activeCallRoomId, '!room:example.com');
      expect(fakeRoom.connected, isTrue);

      states.clear();
      await service.leaveCall();

      expect(service.callState, LatticeCallState.idle);
      expect(states, contains(LatticeCallState.disconnecting));
      expect(states.last, LatticeCallState.idle);
      expect(service.activeGroupCall, isNull);
      expect(service.livekitRoom, isNull);
      verify(mockGroupCall.leave()).called(1);
    });

    test('delegate callback during join does not disrupt call', () async {
      final enterCompleter = Completer<void>();
      when(mockGroupCall.enter()).thenAnswer((_) => enterCompleter.future);

      final joinFuture = service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.isJoining, isTrue);

      service.simulateCallEnded();

      expect(
        service.callState,
        isNot(LatticeCallState.idle),
        reason: 'delegate callback must not interfere during join',
      );

      enterCompleter.complete();
      await joinFuture;

      expect(service.callState, LatticeCallState.connected);
    });

    test('MatrixRTC ended event during join does not disrupt call', () async {
      final enterCompleter = Completer<void>();
      when(mockGroupCall.enter()).thenAnswer((_) => enterCompleter.future);

      final joinFuture = service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );
      await Future<void>.delayed(Duration.zero);

      eventStream.add(GroupCallStateChanged(GroupCallState.ended));
      await Future<void>.delayed(Duration.zero);

      expect(service.activeGroupCall, isNotNull);

      enterCompleter.complete();
      await joinFuture;

      expect(service.callState, LatticeCallState.connected);
    });

    test('joinCall failure does not leave ghost membership', () async {
      fakeRoom.throwOnConnect = true;

      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.failed);
      expect(service.activeGroupCall, isNull);
      verify(mockGroupCall.leave()).called(1);
    });

    test('callElapsed is set after connection', () async {
      expect(service.callElapsed, isNull);

      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.connected);
      expect(service.callElapsed, isNotNull);
    });

    test('second joinCall rejected while first in progress', () async {
      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );
      expect(service.callState, LatticeCallState.connected);
      expect(service.activeCallRoomId, '!room:example.com');
    });
  });

  group('E2E: incoming call lifecycle (callee)', () {
    late MockRoom mockRoom;
    late _FakeLiveKitRoom fakeRoom;
    late MockGroupCallSession mockGroupCall;

    final livekitBackend = LiveKitBackend(
      livekitServiceUrl: 'https://lk-jwt.example.com/token',
      livekitAlias: '#room:example.com',
    );

    setUp(() {
      mockRoom = MockRoom();
      fakeRoom = setupLiveKitMocks();
      final result = setupGroupCall(mockRoom);
      mockGroupCall = result.groupCall;

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    });

    void simulateIncoming() {
      service.simulateIncomingGroupCall(mockGroupCall);
    }

    test('receive → ringing → accept → joining transition', () async {
      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      simulateIncoming();

      expect(service.callState, LatticeCallState.ringingIncoming);
      expect(service.incomingCall, isNotNull);
      expect(service.incomingCall!.roomId, '!room:example.com');
      expect(service.incomingCall!.callerName, 'Test Room');

      states.clear();
      service.acceptCall();

      expect(service.callState, LatticeCallState.joining);
      expect(service.incomingCall, isNull);
      expect(states.first, LatticeCallState.joining);
    });

    test('callee join → connect → leave with explicit params', () async {
      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.connected);
      expect(fakeRoom.connected, isTrue);
      verify(mockGroupCall.enter()).called(1);

      await service.leaveCall();
      expect(service.callState, LatticeCallState.idle);
      verify(mockGroupCall.leave()).called(1);
    });

    test('decline incoming call', () {
      simulateIncoming();
      expect(service.callState, LatticeCallState.ringingIncoming);

      service.declineCall();
      expect(service.callState, LatticeCallState.idle);
      expect(service.incomingCall, isNull);
    });

    test('incoming call ignored when already in a call', () async {
      await service.joinCall(
        '!room:example.com',
        backend: livekitBackend,
        groupCallId: 'call_1',
      );
      expect(service.callState, LatticeCallState.connected);

      final otherGroupCall = MockGroupCallSession();
      final otherRoom = MockRoom();
      when(otherGroupCall.room).thenReturn(otherRoom);
      when(otherRoom.id).thenReturn('!other:example.com');
      when(otherRoom.states).thenReturn({});
      when(otherRoom.getLocalizedDisplayname()).thenReturn('Other Room');

      service.simulateIncomingGroupCall(otherGroupCall);

      expect(service.callState, LatticeCallState.connected);
      expect(service.incomingCall, isNull);
      expect(service.activeCallRoomId, '!room:example.com');
    });

    test('accept does nothing when not in ringing state', () {
      service.acceptCall();
      expect(service.callState, LatticeCallState.idle);
    });

    test('1:1 incoming call sets caller name from remote user', () {
      final mockCallSession = MockCallSession();
      final mockUser = MockUser();

      when(mockCallSession.room).thenReturn(mockRoom);
      when(mockCallSession.remoteUserId).thenReturn('@alice:example.com');
      when(mockCallSession.type).thenReturn(CallType.kVideo);
      when(mockRoom.unsafeGetUserFromMemoryOrFallback('@alice:example.com'))
          .thenReturn(mockUser);
      when(mockUser.calcDisplayname()).thenReturn('Alice');
      when(mockUser.avatarUrl).thenReturn(null);

      service.simulateIncomingCall(mockCallSession);

      expect(service.callState, LatticeCallState.ringingIncoming);
      expect(service.incomingCall!.callerName, 'Alice');
      expect(service.incomingCall!.isVideo, isTrue);
    });

    test('incomingCallStream emits on incoming call', () async {
      final events = <Object>[];
      service.incomingCallStream.listen(events.add);

      simulateIncoming();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
    });
  });

  group('E2E: call reconnection and recovery', () {
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
      expect(service.callState, LatticeCallState.connected);
    });

    test('reconnect cycle: connected → reconnecting → connected', () {
      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      fakeRoom._listener!.fire(const livekit.RoomReconnectingEvent());
      expect(service.callState, LatticeCallState.reconnecting);

      fakeRoom._listener!.fire(const livekit.RoomReconnectedEvent());
      expect(service.callState, LatticeCallState.connected);

      expect(states, [
        LatticeCallState.reconnecting,
        LatticeCallState.connected,
      ]);
    });

    test('disconnect cleans up everything and leaves group call', () async {
      fakeRoom._listener!.fire(livekit.RoomDisconnectedEvent());
      await Future<void>.delayed(Duration.zero);

      expect(service.callState, LatticeCallState.failed);
      expect(service.activeGroupCall, isNull);
      expect(service.livekitRoom, isNull);
      expect(service.participants, isEmpty);
      expect(fakeRoom.disconnected, isTrue);
      verify(mockGroupCall.leave()).called(1);
    });

    test('multiple reconnect events handled correctly', () {
      fakeRoom._listener!.fire(const livekit.RoomReconnectingEvent());
      expect(service.callState, LatticeCallState.reconnecting);

      fakeRoom._listener!.fire(const livekit.RoomReconnectingEvent());
      expect(service.callState, LatticeCallState.reconnecting);

      fakeRoom._listener!.fire(const livekit.RoomReconnectedEvent());
      expect(service.callState, LatticeCallState.connected);
    });
  });

  group('E2E: concurrent and edge-case scenarios', () {
    test('joinCall from failed state succeeds', () async {
      final mockRoom = MockRoom();
      final fakeRoom = setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      fakeRoom.throwOnConnect = true;
      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );
      expect(service.callState, LatticeCallState.failed);

      fakeRoom.throwOnConnect = false;
      final fakeRoom2 = _FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom2;

      final mockGroupCall2 = MockGroupCallSession();
      final eventStream2 = CachedStreamController<MatrixRTCCallEvent>();
      when(mockGroupCall2.room).thenReturn(mockRoom);
      when(mockGroupCall2.groupCallId).thenReturn('call_1');
      when(mockGroupCall2.matrixRTCEventStream).thenReturn(eventStream2);
      when(mockGroupCall2.enter()).thenAnswer((_) async {});
      when(mockGroupCall2.leave()).thenAnswer((_) async {});
      final voipId = VoipId(roomId: '!room:example.com', callId: 'call_1');
      when(mockVoip.groupCalls).thenReturn({voipId: mockGroupCall2});

      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.connected);
      expect(fakeRoom2.connected, isTrue);
    });

    test('state transitions during join → connect → leave', () async {
      final mockRoom = MockRoom();
      setupLiveKitMocks();
      setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      await service.joinCall(
        '!room:example.com',
        backend: LiveKitBackend(
          livekitServiceUrl: 'https://lk-jwt.example.com/token',
          livekitAlias: '#room:example.com',
        ),
        groupCallId: 'call_1',
      );

      expect(states.first, LatticeCallState.joining);
      expect(states.last, LatticeCallState.connected);

      states.clear();
      await service.leaveCall();

      expect(states.first, LatticeCallState.disconnecting);
      expect(states.last, LatticeCallState.idle);
    });

    test('client update during active call resets everything', () async {
      final mockRoom = MockRoom();
      setupLiveKitMocks();
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
      expect(service.callState, LatticeCallState.connected);

      final newClient = MockClient();
      when(newClient.rooms).thenReturn([]);
      service.updateClient(newClient);

      expect(service.callState, LatticeCallState.idle);
      expect(service.activeGroupCall, isNull);
      expect(service.livekitRoom, isNull);
    });
  });

  group('E2E: MeshBackend call lifecycle', () {
    test('join with MeshBackend succeeds without LiveKit', () async {
      final mockRoom = MockRoom();
      final result = setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await service.joinCall(
        '!room:example.com',
        backend: MeshBackend(),
        groupCallId: 'call_1',
      );

      expect(service.callState, LatticeCallState.connected);
      expect(service.livekitRoom, isNull);
      expect(service.activeGroupCall, same(result.groupCall));
      verify(result.groupCall.enter()).called(1);
    });

    test('leave MeshBackend call', () async {
      final mockRoom = MockRoom();
      final result = setupGroupCall(mockRoom);

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await service.joinCall(
        '!room:example.com',
        backend: MeshBackend(),
        groupCallId: 'call_1',
      );

      await service.leaveCall();

      expect(service.callState, LatticeCallState.idle);
      expect(service.activeGroupCall, isNull);
      verify(result.groupCall.leave()).called(1);
    });
  });

  group('E2E: track toggles during active call', () {
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

    test('full toggle sequence: mic → camera → screenshare', () async {
      expect(service.isMicEnabled, isFalse);
      expect(service.isCameraEnabled, isFalse);
      expect(service.isScreenShareEnabled, isFalse);

      await service.toggleMicrophone();
      expect(service.isMicEnabled, isTrue);

      await service.toggleCamera();
      expect(service.isCameraEnabled, isTrue);

      await service.toggleScreenShare();
      expect(service.isScreenShareEnabled, isTrue);

      await service.toggleMicrophone();
      expect(service.isMicEnabled, isFalse);
      expect(service.isCameraEnabled, isTrue);
      expect(service.isScreenShareEnabled, isTrue);
    });

    test('toggle error does not affect other toggles', () async {
      await service.toggleMicrophone();
      expect(service.isMicEnabled, isTrue);

      fakeRoom._localParticipant!.throwOnToggle = true;

      await service.toggleCamera();
      expect(service.isCameraEnabled, isFalse);

      expect(service.isMicEnabled, isTrue);
    });
  });

  group('E2E: participant aggregation', () {
    test('allParticipants includes local after LiveKit connect', () async {
      final mockRoom = MockRoom();
      setupLiveKitMocks();
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

      final participants = service.allParticipants;
      expect(participants, hasLength(1));
      expect(participants.first.isLocal, isTrue);
    });

    test('allParticipants updates when remote joins', () async {
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

      final fakeRemote = _FakeRemoteParticipant();
      fakeRoom._remoteParticipants['user2'] = fakeRemote;
      fakeRoom._listener!.fire(
        livekit.ParticipantConnectedEvent(participant: fakeRemote),
      );

      final participants = service.allParticipants;
      expect(participants, hasLength(2));
    });

    test('allParticipants empty when no active call', () {
      expect(service.allParticipants, isEmpty);
    });
  });
}

// ── Fake RemoteParticipant ─────────────────────────────────

class _FakeRemoteParticipant extends Fake
    implements livekit.RemoteParticipant {
  @override
  List<livekit.RemoteTrackPublication<livekit.RemoteVideoTrack>>
      get videoTrackPublications => [];

  @override
  String get identity => 'remote';

  @override
  String get name => 'Remote User';

  @override
  bool get isMuted => false;
}

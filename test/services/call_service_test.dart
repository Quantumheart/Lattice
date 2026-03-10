import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/core/services/call_service.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import 'call_service_test.mocks.dart';

// ── LiveKit Mocks ─────────────────────────────────────────

class _MockLocalParticipant extends Fake implements livekit.LocalParticipant {
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
  double get audioLevel => 0;

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

class _FakeEventsListener<T> extends Fake implements livekit.EventsListener<T> {
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
      get remoteParticipants => UnmodifiableMapView(_remoteParticipants);

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

class _FakeRemoteParticipant extends Fake implements livekit.RemoteParticipant {
  @override
  List<livekit.RemoteTrackPublication<livekit.RemoteVideoTrack>>
      get videoTrackPublications => [];

  @override
  String get identity => 'remote';

  @override
  String get name => 'Remote User';

  @override
  bool get isMuted => false;

  @override
  double get audioLevel => 0;
}

void main() {
  late MockClient mockClient;
  late CallService service;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.userID).thenReturn('@user:example.com');
    when(mockClient.deviceID).thenReturn('DEVICE1');
    service = CallService(client: mockClient);
  });

  _FakeLiveKitRoom setupLiveKitMocks() {
    final fakeRoom = _FakeLiveKitRoom();
    service.roomFactoryForTest = () => fakeRoom;

    when(mockClient.requestOpenIdToken(any, any)).thenAnswer(
      (_) async => OpenIdCredentials(
        accessToken: 'openid_token',
        expiresIn: 3600,
        matrixServerName: 'example.com',
        tokenType: 'Bearer',
      ),
    );

    when(mockClient.setRoomStateWithKey(any, any, any, any))
        .thenAnswer((_) async => 'event_id');

    service.httpPostForTest = (url, {headers, body}) async {
      return http.Response(
        jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'lk_token'}),
        200,
      );
    };

    service.cachedLivekitServiceUrlForTest = 'https://lk-jwt.example.com';

    return fakeRoom;
  }

  MockRoom setupMockRoom() {
    final mockRoom = MockRoom();
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.canonicalAlias).thenReturn('#room:example.com');
    when(mockRoom.states).thenReturn({});
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    return mockRoom;
  }

  group('CallService initial state', () {
    test('callState starts as idle', () {
      expect(service.callState, LatticeCallState.idle);
    });

    test('activeCallRoomId starts as null', () {
      expect(service.activeCallRoomId, isNull);
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

  group('joinCall', () {
    test('sends membership state event and connects to LiveKit', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.connected);
      expect(service.activeCallRoomId, '!room:example.com');
      expect(service.livekitRoom, isNotNull);

      verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          'org.matrix.msc3401.call.member',
          '_@user:example.com_DEVICE1_m.call',
          argThat(containsPair('application', 'm.call')),
        ),
      ).called(1);
    });

    test('requires LiveKit service URL', () async {
      setupLiveKitMocks();
      setupMockRoom();
      service.cachedLivekitServiceUrlForTest = null;

      service.httpPostForTest = (url, {headers, body}) async {
        return http.Response('', 404);
      };

      when(mockClient.getWellknown()).thenThrow(Exception('no well-known'));

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.failed);
    });

    test('returns early when room not found', () async {
      setupLiveKitMocks();
      when(mockClient.getRoomById('!missing:example.com')).thenReturn(null);

      service
        ..cachedLivekitServiceUrlForTest = 'https://lk.example.com'
        ..init();
      await service.joinCall('!missing:example.com');

      expect(service.callState, LatticeCallState.idle);
    });

    test('rejects concurrent join attempts', () async {
      final completer = Completer<void>();
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      fakeRoom.throwOnConnect = false;

      final originalPost = service.httpPostForTest;
      service.httpPostForTest = (url, {headers, body}) async {
        await completer.future;
        return originalPost(url, headers: headers, body: body);
      };

      final firstJoin = service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.joining);

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.joining);

      completer.complete();
      await firstJoin;
    });

    test('only allows join from valid states', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.connected);

      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.failed);
    });

    test('cleans up on LiveKit connect failure', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();
      fakeRoom.throwOnConnect = true;

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.failed);
      expect(service.activeCallRoomId, isNull);
      expect(service.livekitRoom, isNull);

      verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          'org.matrix.msc3401.call.member',
          '_@user:example.com_DEVICE1_m.call',
          {},
        ),
      ).called(1);
    });

    test('cleans up on token exchange failure', () async {
      setupLiveKitMocks();
      setupMockRoom();

      service.httpPostForTest = (url, {headers, body}) async {
        return http.Response('token error', 500);
      };

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.failed);
      expect(service.activeCallRoomId, isNull);
    });
  });

  group('joinCall failure cleans up membership', () {
    test('removes membership event when LiveKit connect fails', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();
      fakeRoom.throwOnConnect = true;

      await service.joinCall('!room:example.com');

      final verifyResult = verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          'org.matrix.msc3401.call.member',
          '_@user:example.com_DEVICE1_m.call',
          captureAny,
        ),
      );
      verifyResult.called(2);

      final calls = verifyResult.captured;
      expect(calls.first, containsPair('application', 'm.call'));
      expect(calls.last, isEmpty);
    });

    test('removes membership event when token exchange fails', () async {
      setupLiveKitMocks();
      setupMockRoom();

      service.httpPostForTest = (url, {headers, body}) async {
        return http.Response('error', 500);
      };

      await service.joinCall('!room:example.com');

      verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          'org.matrix.msc3401.call.member',
          '_@user:example.com_DEVICE1_m.call',
          {},
        ),
      ).called(1);
    });

    test('membership removal error in catch block is handled gracefully',
        () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();
      fakeRoom.throwOnConnect = true;

      var callCount = 0;
      when(mockClient.setRoomStateWithKey(any, any, any, any))
          .thenAnswer((_) async {
        callCount++;
        if (callCount == 2) throw Exception('leave error');
        return 'event_id';
      });

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.failed);
    });
  });

  group('leaveCall', () {
    test('disconnects LiveKit and removes membership', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.connected);

      await service.leaveCall();

      expect(service.callState, LatticeCallState.idle);
      expect(service.activeCallRoomId, isNull);
      expect(service.livekitRoom, isNull);
      expect(fakeRoom.disconnected, isTrue);

      verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          'org.matrix.msc3401.call.member',
          '_@user:example.com_DEVICE1_m.call',
          {},
        ),
      ).called(1);
    });

    test('does nothing when no active call', () async {
      await service.leaveCall();
      expect(service.callState, LatticeCallState.idle);
    });

    test('handles membership removal error gracefully', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      when(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          'org.matrix.msc3401.call.member',
          any,
          {},
        ),
      ).thenThrow(Exception('remove error'));

      await service.leaveCall();

      expect(service.callState, LatticeCallState.idle);
    });
  });

  group('LiveKit events', () {
    test('reconnecting event sets reconnecting state', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      fakeRoom._listener!.fire(const livekit.RoomReconnectingEvent());

      expect(service.callState, LatticeCallState.reconnecting);
    });

    test('reconnected event sets connected state', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      fakeRoom._listener!.fire(const livekit.RoomReconnectedEvent());

      expect(service.callState, LatticeCallState.connected);
    });

    test('disconnect event cleans up and removes membership', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      fakeRoom._listener!.fire(livekit.RoomDisconnectedEvent());

      expect(service.callState, LatticeCallState.failed);
      expect(service.activeCallRoomId, isNull);

      await Future<void>.delayed(Duration.zero);

      verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          'org.matrix.msc3401.call.member',
          '_@user:example.com_DEVICE1_m.call',
          {},
        ),
      ).called(1);
    });

    test('participants sync on connect/disconnect events', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      expect(service.participants, isEmpty);

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

    test('active speakers update on event', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      fakeRoom._listener!.fire(
        livekit.ActiveSpeakersChangedEvent(
          speakers: [fakeRoom._localParticipant!],
        ),
      );

      expect(service.activeSpeakers, hasLength(1));
    });
  });

  group('track toggles', () {
    late _FakeLiveKitRoom fakeRoom;

    setUp(() async {
      fakeRoom = setupLiveKitMocks();
      setupMockRoom();
      await service.joinCall('!room:example.com');
    });

    test('toggleMicrophone enables then disables', () async {
      expect(service.isMicEnabled, isFalse);

      await service.toggleMicrophone();
      expect(service.isMicEnabled, isTrue);
      expect(fakeRoom._localParticipant!.micEnabled, isTrue);

      await service.toggleMicrophone();
      expect(service.isMicEnabled, isFalse);
      expect(fakeRoom._localParticipant!.micEnabled, isFalse);
    });

    test('toggleCamera enables then disables', () async {
      expect(service.isCameraEnabled, isFalse);

      await service.toggleCamera();
      expect(service.isCameraEnabled, isTrue);
      expect(fakeRoom._localParticipant!.cameraEnabled, isTrue);

      await service.toggleCamera();
      expect(service.isCameraEnabled, isFalse);
      expect(fakeRoom._localParticipant!.cameraEnabled, isFalse);
    });

    test('toggleScreenShare enables then disables', () async {
      expect(service.isScreenShareEnabled, isFalse);

      await service.toggleScreenShare();
      expect(service.isScreenShareEnabled, isTrue);
      expect(fakeRoom._localParticipant!.screenShareEnabled, isTrue);

      await service.toggleScreenShare();
      expect(service.isScreenShareEnabled, isFalse);
      expect(fakeRoom._localParticipant!.screenShareEnabled, isFalse);
    });

    test('toggle reverts on error', () async {
      await service.toggleMicrophone();
      expect(service.isMicEnabled, isTrue);

      fakeRoom._localParticipant!.throwOnToggle = true;

      await service.toggleMicrophone();
      expect(service.isMicEnabled, isTrue);
    });

    test('toggle does nothing without LiveKit room', () async {
      final standalone = CallService(client: mockClient);

      await standalone.toggleMicrophone();
      expect(standalone.isMicEnabled, isFalse);

      await standalone.toggleCamera();
      expect(standalone.isCameraEnabled, isFalse);

      await standalone.toggleScreenShare();
      expect(standalone.isScreenShareEnabled, isFalse);
    });
  });

  group('ringing actions', () {
    test('declineCall resets state', () {
      service.declineCall();
      expect(service.callState, LatticeCallState.idle);
    });

    test('cancelOutgoingCall resets state', () {
      service.cancelOutgoingCall();
      expect(service.callState, LatticeCallState.idle);
    });
  });

  group('handleCallEnded', () {
    test('resets ringing state', () {
      service.simulateCallEnded();
      expect(service.callState, LatticeCallState.idle);
    });
  });

  group('roomHasActiveCall', () {
    test('returns false when room not found', () {
      when(mockClient.getRoomById('!missing:example.com')).thenReturn(null);
      expect(service.roomHasActiveCall('!missing:example.com'), isFalse);
    });

    test('returns false when no call member state events', () {
      final mockRoom = setupMockRoom();
      when(mockRoom.states).thenReturn({});
      expect(service.roomHasActiveCall('!room:example.com'), isFalse);
    });

    test('returns true when active membership exists', () {
      final mockRoom = setupMockRoom();
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        'org.matrix.msc3401.call.member': {
          '_@alice:example.com_DEVICE_m.call': FakeEvent(
            content: {
              'application': 'm.call',
              'call_id': '',
              'scope': 'm.room',
              'device_id': 'DEVICE',
              'expires': 14400000,
            },
            originServerTs: now,
          ),
        },
      });
      expect(service.roomHasActiveCall('!room:example.com'), isTrue);
    });

    test('returns false when membership is expired', () {
      final mockRoom = setupMockRoom();
      final longAgo = DateTime.now()
          .subtract(const Duration(hours: 5))
          .millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        'org.matrix.msc3401.call.member': {
          '_@alice:example.com_DEVICE_m.call': FakeEvent(
            content: {
              'application': 'm.call',
              'call_id': '',
              'expires': 1000,
            },
            originServerTs: longAgo,
          ),
        },
      });
      expect(service.roomHasActiveCall('!room:example.com'), isFalse);
    });
  });

  group('callParticipantCount', () {
    test('counts active memberships for a call id', () {
      final mockRoom = setupMockRoom();
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        'org.matrix.msc3401.call.member': {
          '_@alice:example.com_DEV1_m.call': FakeEvent(
            content: {
              'application': 'm.call',
              'call_id': '',
              'expires': 14400000,
            },
            originServerTs: now,
          ),
          '_@bob:example.com_DEV2_m.call': FakeEvent(
            content: {
              'application': 'm.call',
              'call_id': '',
              'expires': 14400000,
            },
            originServerTs: now,
          ),
        },
      });
      expect(service.callParticipantCount('!room:example.com', ''), 2);
    });
  });

  group('E2E: outgoing call lifecycle', () {
    test('initiateCall joins and connects', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.initiateCall('!room:example.com');

      expect(service.callState, LatticeCallState.connected);
      expect(service.activeCallRoomId, '!room:example.com');
    });

    test('cancelOutgoingCall during join sets ended flag', () async {
      final completer = Completer<void>();
      setupLiveKitMocks();
      setupMockRoom();

      final originalPost = service.httpPostForTest;
      service.httpPostForTest = (url, {headers, body}) async {
        await completer.future;
        return originalPost(url, headers: headers, body: body);
      };

      final joinFuture = service.initiateCall('!room:example.com');

      await Future<void>.delayed(Duration.zero);
      expect(service.callState, LatticeCallState.ringingOutgoing);

      service.cancelOutgoingCall();

      completer.complete();
      await joinFuture;

      expect(service.callState, LatticeCallState.idle);
    });
  });

  group('E2E: concurrent and edge-case scenarios', () {
    test('joinCall from failed state succeeds', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();
      fakeRoom.throwOnConnect = true;

      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.failed);

      fakeRoom.throwOnConnect = false;
      final freshRoom = _FakeLiveKitRoom();
      service.roomFactoryForTest = () => freshRoom;

      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.connected);
    });

    test('second joinCall ignored while first in progress', () async {
      final completer = Completer<void>();
      setupLiveKitMocks();
      setupMockRoom();

      final originalPost = service.httpPostForTest;
      service.httpPostForTest = (url, {headers, body}) async {
        await completer.future;
        return originalPost(url, headers: headers, body: body);
      };

      final firstJoin = service.joinCall('!room:example.com');

      await Future<void>.delayed(Duration.zero);

      await service.joinCall('!room:example.com');

      expect(service.isJoining, isTrue);

      completer.complete();
      await firstJoin;
    });
  });

  group('E2E: participant aggregation', () {
    test('allParticipants includes local after LiveKit connect', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      final participants = service.allParticipants;
      expect(participants, hasLength(1));
      expect(participants.first.isLocal, isTrue);
    });

    test('allParticipants updates when remote joins', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

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

  group('token exchange', () {
    test('tries get_token first, falls back to sfu/get on 404', () async {
      setupLiveKitMocks();
      setupMockRoom();

      final requestedUrls = <String>[];
      service.httpPostForTest = (url, {headers, body}) async {
        requestedUrls.add(url.toString());
        if (url.path.contains('get_token')) {
          return http.Response('', 404);
        }
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'token': 'lk_token'}),
          200,
        );
      };

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.connected);
      expect(requestedUrls.any((u) => u.contains('get_token')), isTrue);
      expect(requestedUrls.any((u) => u.contains('sfu/get')), isTrue);
    });

    test('follows 307 redirects', () async {
      setupLiveKitMocks();
      setupMockRoom();

      var callCount = 0;
      service.httpPostForTest = (url, {headers, body}) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            '',
            307,
            headers: {
              'location': 'https://lk-jwt.example.com/get_token/',
            },
          );
        }
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'lk_token'}),
          200,
        );
      };

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.connected);
      expect(callCount, 2);
    });
  });

  group('membership state event format', () {
    test('sends correct MSC3401 membership content', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      final captured = verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          'org.matrix.msc3401.call.member',
          '_@user:example.com_DEVICE1_m.call',
          captureAny,
        ),
      ).captured;

      final content = captured.first as Map<String, dynamic>;
      expect(content['application'], 'm.call');
      expect(content['call_id'], '');
      expect(content['scope'], 'm.room');
      expect(content['device_id'], 'DEVICE1');
      expect(content['expires'], 14400000);
      expect(content['focus_active'], {
        'type': 'livekit',
        'focus_selection': 'oldest_membership',
      });
      expect(content['foci_preferred'], [
        {
          'type': 'livekit',
          'livekit_service_url': 'https://lk-jwt.example.com',
          'livekit_alias': '#room:example.com',
        },
      ]);
    });

    test('sends empty content on leave', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');
      await service.leaveCall();

      verify(
        mockClient.setRoomStateWithKey(
          '!room:example.com',
          'org.matrix.msc3401.call.member',
          '_@user:example.com_DEVICE1_m.call',
          {},
        ),
      ).called(1);
    });
  });

  group('updateClient', () {
    test('resets state on client change', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.connected);

      final newClient = MockClient();
      when(newClient.rooms).thenReturn([]);
      service.updateClient(newClient);

      expect(service.callState, LatticeCallState.idle);
      expect(service.activeCallRoomId, isNull);
    });

    test('no-op when same client', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');
      service.updateClient(mockClient);

      expect(service.callState, LatticeCallState.connected);
    });
  });
}

// ── Fake Event for room state testing ─────────────────────

class FakeEvent extends Fake implements Event {
  FakeEvent({required this.content, required int originServerTs})
      : originServerTs = DateTime.fromMillisecondsSinceEpoch(originServerTs);

  @override
  final Map<String, dynamic> content;

  @override
  final DateTime originServerTs;
}

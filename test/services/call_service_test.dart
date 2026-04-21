import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kohera/core/services/call_service.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import 'call_service_test.mocks.dart';
import 'call_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient mockClient;
  late CallService service;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.userID).thenReturn('@user:example.com');
    when(mockClient.deviceID).thenReturn('DEVICE1');
    when(mockClient.onTimelineEvent).thenReturn(CachedStreamController<Event>());
    when(mockClient.onRoomState).thenReturn(
      CachedStreamController<({String roomId, StrippedStateEvent state})>(),
    );
    service = CallService(client: mockClient);
  });

  FakeLiveKitRoom setupLiveKitMocks() {
    final fakeRoom = FakeLiveKitRoom();
    service.roomFactoryForTest = ({roomOptions}) => fakeRoom;

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

    service.httpPostForTest = (client, url, {headers, body}) async {
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
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.unsafeGetUserFromMemoryOrFallback(any)).thenAnswer(
      (invocation) => User(
        invocation.positionalArguments[0] as String,
        room: mockRoom,
      ),
    );
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    return mockRoom;
  }

  group('CallService initial state', () {
    test('callState starts as idle', () {
      expect(service.callState, KoheraCallState.idle);
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

      expect(service.callState, KoheraCallState.connected);
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

      service.httpPostForTest = (client, url, {headers, body}) async {
        return http.Response('', 404);
      };

      when(mockClient.getWellknown()).thenThrow(Exception('no well-known'));

      await service.joinCall('!room:example.com');

      expect(service.callState, KoheraCallState.failed);
    });

    test('returns early when room not found', () async {
      setupLiveKitMocks();
      when(mockClient.getRoomById('!missing:example.com')).thenReturn(null);

      service
        ..cachedLivekitServiceUrlForTest = 'https://lk.example.com'
        ..init();
      await service.joinCall('!missing:example.com');

      expect(service.callState, KoheraCallState.idle);
    });

    test('rejects concurrent join attempts', () async {
      final completer = Completer<void>();
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      fakeRoom.throwOnConnect = false;

      final originalPost = service.httpPostForTest;
      service.httpPostForTest = (client, url, {headers, body}) async {
        await completer.future;
        return originalPost(client, url, headers: headers, body: body);
      };

      final firstJoin = service.joinCall('!room:example.com');

      expect(service.callState, KoheraCallState.joining);

      await service.joinCall('!room:example.com');

      expect(service.callState, KoheraCallState.joining);

      completer.complete();
      await firstJoin;
    });

    test('only allows join from valid states', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');
      expect(service.callState, KoheraCallState.connected);

      await service.joinCall('!room:example.com');
      expect(service.callState, KoheraCallState.connected);
    });

    test('cleans up on LiveKit connect failure', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();
      fakeRoom.throwOnConnect = true;

      await service.joinCall('!room:example.com');

      expect(service.callState, KoheraCallState.failed);
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

      service.httpPostForTest = (client, url, {headers, body}) async {
        return http.Response('token error', 500);
      };

      await service.joinCall('!room:example.com');

      expect(service.callState, KoheraCallState.failed);
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

      service.httpPostForTest = (client, url, {headers, body}) async {
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

      expect(service.callState, KoheraCallState.failed);
    });
  });

  group('leaveCall', () {
    test('disconnects LiveKit and removes membership', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');
      expect(service.callState, KoheraCallState.connected);

      await service.leaveCall();

      expect(service.callState, KoheraCallState.idle);
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
      expect(service.callState, KoheraCallState.idle);
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

      expect(service.callState, KoheraCallState.idle);
    });
  });

  group('LiveKit events', () {
    test('reconnecting event sets reconnecting state', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      fakeRoom.listener!.fire(const livekit.RoomReconnectingEvent());
      await Future<void>.delayed(Duration.zero);

      expect(service.callState, KoheraCallState.reconnecting);
    });

    test('reconnected event sets connected state', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      fakeRoom.listener!.fire(const livekit.RoomReconnectedEvent());
      await Future<void>.delayed(Duration.zero);

      expect(service.callState, KoheraCallState.connected);
    });

    test('disconnect event cleans up and removes membership', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      fakeRoom.listener!.fire(livekit.RoomDisconnectedEvent());
      await Future<void>.delayed(Duration.zero);

      expect(service.callState, KoheraCallState.failed);
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

      final fakeRemote = FakeRemoteParticipant();
      fakeRoom.remoteParticipantsMap['user2'] = fakeRemote;
      fakeRoom.listener!.fire(
        livekit.ParticipantConnectedEvent(participant: fakeRemote),
      );

      expect(service.participants, hasLength(1));

      fakeRoom.remoteParticipantsMap.remove('user2');
      fakeRoom.listener!.fire(
        livekit.ParticipantDisconnectedEvent(participant: fakeRemote),
      );

      expect(service.participants, isEmpty);
    });

    test('active speakers update on event', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');

      fakeRoom.listener!.fire(
        livekit.ActiveSpeakersChangedEvent(
          speakers: [fakeRoom.localParticipantFake!],
        ),
      );

      expect(service.activeSpeakers, hasLength(1));
    });
  });

  group('track toggles', () {
    late FakeLiveKitRoom fakeRoom;

    setUp(() async {
      fakeRoom = setupLiveKitMocks();
      setupMockRoom();
      await service.joinCall('!room:example.com');
    });

    test('toggleMicrophone disables then enables', () async {
      expect(service.isMicEnabled, isTrue);

      await service.toggleMicrophone();
      expect(service.isMicEnabled, isFalse);
      expect(fakeRoom.localParticipantFake!.micEnabled, isFalse);

      await service.toggleMicrophone();
      expect(service.isMicEnabled, isTrue);
      expect(fakeRoom.localParticipantFake!.micEnabled, isTrue);
    });

    test('toggleCamera enables then disables', () async {
      expect(service.isCameraEnabled, isFalse);

      await service.toggleCamera();
      expect(service.isCameraEnabled, isTrue);
      expect(fakeRoom.localParticipantFake!.cameraEnabled, isTrue);

      await service.toggleCamera();
      expect(service.isCameraEnabled, isFalse);
      expect(fakeRoom.localParticipantFake!.cameraEnabled, isFalse);
    });

    test('toggleScreenShare enables then disables', () async {
      expect(service.isScreenShareEnabled, isFalse);

      await service.toggleScreenShare();
      expect(service.isScreenShareEnabled, isTrue);
      expect(fakeRoom.localParticipantFake!.screenShareEnabled, isTrue);

      await service.toggleScreenShare();
      expect(service.isScreenShareEnabled, isFalse);
      expect(fakeRoom.localParticipantFake!.screenShareEnabled, isFalse);
    });

    test('toggle reverts on error', () async {
      expect(service.isMicEnabled, isTrue);

      fakeRoom.localParticipantFake!.throwOnToggle = true;

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
      expect(service.callState, KoheraCallState.idle);
    });

    test('cancelOutgoingCall resets state', () {
      service.cancelOutgoingCall();
      expect(service.callState, KoheraCallState.idle);
    });
  });

  group('handleCallEnded', () {
    test('resets ringing state', () {
      service.simulateCallEnded();
      expect(service.callState, KoheraCallState.idle);
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
    test('initiateCall sends invite and stays ringingOutgoing', () async {
      setupLiveKitMocks();
      final room = setupMockRoom();
      when(room.sendEvent(any, type: anyNamed('type')))
          .thenAnswer((_) async => 'event_id');
      when(room.isDirectChat).thenReturn(true);

      await service.initiateCall('!room:example.com');

      expect(service.callState, KoheraCallState.ringingOutgoing);
      expect(service.activeCallId, isNotNull);
    });

    test('cancelOutgoingCall sends hangup and returns to idle', () async {
      setupLiveKitMocks();
      final room = setupMockRoom();
      when(room.sendEvent(any, type: anyNamed('type')))
          .thenAnswer((_) async => 'event_id');
      when(room.isDirectChat).thenReturn(true);

      await service.initiateCall('!room:example.com');
      expect(service.callState, KoheraCallState.ringingOutgoing);

      service.cancelOutgoingCall();

      expect(service.callState, KoheraCallState.idle);
    });
  });

  group('E2E: concurrent and edge-case scenarios', () {
    test('joinCall from failed state succeeds', () async {
      final fakeRoom = setupLiveKitMocks();
      setupMockRoom();
      fakeRoom.throwOnConnect = true;

      await service.joinCall('!room:example.com');
      expect(service.callState, KoheraCallState.failed);

      fakeRoom.throwOnConnect = false;
      final freshRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = ({roomOptions}) => freshRoom;

      await service.joinCall('!room:example.com');
      expect(service.callState, KoheraCallState.connected);
    });

    test('second joinCall ignored while first in progress', () async {
      final completer = Completer<void>();
      setupLiveKitMocks();
      setupMockRoom();

      final originalPost = service.httpPostForTest;
      service.httpPostForTest = (client, url, {headers, body}) async {
        await completer.future;
        return originalPost(client, url, headers: headers, body: body);
      };

      final firstJoin = service.joinCall('!room:example.com');

      await Future<void>.delayed(Duration.zero);

      await service.joinCall('!room:example.com');

      expect(service.callState, KoheraCallState.joining);

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

      final fakeRemote = FakeRemoteParticipant();
      fakeRoom.remoteParticipantsMap['user2'] = fakeRemote;
      fakeRoom.listener!.fire(
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
    test('posts to sfu/get with nested OpenID payload', () async {
      setupLiveKitMocks();
      setupMockRoom();

      Uri? capturedUrl;
      Object? capturedBody;
      service.httpPostForTest = (client, url, {headers, body}) async {
        capturedUrl = url;
        capturedBody = body;
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'lk_token'}),
          200,
        );
      };

      await service.joinCall('!room:example.com');

      expect(service.callState, KoheraCallState.connected);
      expect(capturedUrl.toString(), contains('sfu/get'));
      final decoded = jsonDecode(
        utf8.decode(capturedBody! as List<int>),
      ) as Map<String, dynamic>;
      expect(decoded['room'], '#room:example.com');
      expect(decoded['device_id'], 'DEVICE1');
      expect(decoded.containsKey('slot_id'), isFalse);
      expect(decoded.containsKey('display_name'), isFalse);
      final openIdToken = decoded['openid_token'] as Map<String, dynamic>;
      expect(openIdToken['access_token'], 'openid_token');
      expect(openIdToken['matrix_server_name'], 'example.com');
    });

    test('follows 307 redirects', () async {
      setupLiveKitMocks();
      setupMockRoom();

      var callCount = 0;
      service.httpPostForTest = (client, url, {headers, body}) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            '',
            307,
            headers: {
              'location': 'https://lk-jwt.example.com/sfu/get/',
            },
          );
        }
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'lk_token'}),
          200,
        );
      };

      await service.joinCall('!room:example.com');

      expect(service.callState, KoheraCallState.connected);
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

  group('push call foundation', () {
    late FakeNativeCallUiService fakeNative;
    late CallService pushService;

    setUp(() {
      fakeNative = FakeNativeCallUiService();
      pushService = CallService(
        client: mockClient,
        nativeCallUiService: fakeNative,
      );
    });

    tearDown(() {
      pushService.dispose();
    });

    test('handlePushCallInvite(callKitAlreadyShown: true) skips native show',
        () {
      pushService.handlePushCallInvite(
        roomId: '!room:example.com',
        callId: 'call1',
        callerName: 'Alice',
        isVideo: false,
        callKitAlreadyShown: true,
      );

      expect(pushService.callState, KoheraCallState.ringingIncoming);
      expect(fakeNative.showIncomingCalls, 0);
    });

    test('handlePushCallInvite(callKitAlreadyShown: false) shows native', () {
      pushService.handlePushCallInvite(
        roomId: '!room:example.com',
        callId: 'call1',
        callerName: 'Alice',
        isVideo: false,
      );

      expect(pushService.callState, KoheraCallState.ringingIncoming);
      expect(fakeNative.showIncomingCalls, 1);
    });

    test('handlePushCallInvite ignores duplicate when not idle/failed', () {
      pushService.handlePushCallInvite(
        roomId: '!room:example.com',
        callId: 'call1',
        callerName: 'Alice',
        isVideo: false,
      );
      expect(fakeNative.showIncomingCalls, 1);

      pushService.handlePushCallInvite(
        roomId: '!room:example.com',
        callId: 'call1',
        callerName: 'Alice',
        isVideo: false,
      );

      expect(fakeNative.showIncomingCalls, 1);
      expect(pushService.callState, KoheraCallState.ringingIncoming);
    });

    test('attachPrePresentedCallKit forwards UUID to native service', () {
      pushService.attachPrePresentedCallKit(nativeCallId: 'uuid-1234');

      expect(fakeNative.attachExistingCalls, 1);
      expect(fakeNative.lastAttachedCallId, 'uuid-1234');
    });

    test('endCallFromPushKit dismisses native call when ringingIncoming', () {
      pushService.handlePushCallInvite(
        roomId: '!room:example.com',
        callId: 'call1',
        callerName: 'Alice',
        isVideo: false,
        callKitAlreadyShown: true,
      );
      expect(pushService.callState, KoheraCallState.ringingIncoming);

      final endsBefore = fakeNative.endNativeCalls;
      pushService.endCallFromPushKit();

      expect(fakeNative.endNativeCalls, endsBefore + 1);
      expect(pushService.callState, KoheraCallState.idle);
    });

    test('endCallFromPushKit is a no-op when not ringingIncoming', () {
      expect(pushService.callState, KoheraCallState.idle);

      final endsBefore = fakeNative.endNativeCalls;
      pushService.endCallFromPushKit();

      expect(fakeNative.endNativeCalls, endsBefore);
      expect(pushService.callState, KoheraCallState.idle);
    });
  });

  group('updateClient', () {
    test('resets state on client change', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');
      expect(service.callState, KoheraCallState.connected);

      final newClient = MockClient();
      when(newClient.rooms).thenReturn([]);
      service.updateClient(newClient);

      expect(service.callState, KoheraCallState.idle);
      expect(service.activeCallRoomId, isNull);
    });

    test('no-op when same client', () async {
      setupLiveKitMocks();
      setupMockRoom();

      await service.joinCall('!room:example.com');
      service.updateClient(mockClient);

      expect(service.callState, KoheraCallState.connected);
    });
  });

  group('transition sounds', () {
    late FakeRingtoneService fakeRingtone;
    late CallService soundService;

    setUp(() {
      fakeRingtone = FakeRingtoneService();
      soundService = CallService(
        client: mockClient,
        ringtoneService: fakeRingtone,
      );
    });

    tearDown(() => soundService.dispose());

    test('plays join sound on joining -> connected', () async {
      final fakeRoom = FakeLiveKitRoom();
      soundService.roomFactoryForTest = ({roomOptions}) => fakeRoom;
      when(mockClient.requestOpenIdToken(any, any)).thenAnswer(
        (_) async => OpenIdCredentials(
          accessToken: 't',
          expiresIn: 3600,
          matrixServerName: 'example.com',
          tokenType: 'Bearer',
        ),
      );
      when(mockClient.setRoomStateWithKey(any, any, any, any))
          .thenAnswer((_) async => 'event_id');
      soundService.httpPostForTest = (client, url, {headers, body}) async =>
          http.Response(
            jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'lk_token'}),
            200,
          );
      soundService.cachedLivekitServiceUrlForTest = 'https://lk-jwt.example.com';
      setupMockRoom();

      await soundService.joinCall('!room:example.com');

      expect(soundService.callState, KoheraCallState.connected);
      expect(fakeRingtone.userJoinedCalls, 1);
      expect(fakeRingtone.userLeftCalls, 0);
    });

    test('plays leave sound on connected -> idle (leaveCall)', () async {
      final fakeRoom = FakeLiveKitRoom();
      soundService.roomFactoryForTest = ({roomOptions}) => fakeRoom;
      when(mockClient.requestOpenIdToken(any, any)).thenAnswer(
        (_) async => OpenIdCredentials(
          accessToken: 't',
          expiresIn: 3600,
          matrixServerName: 'example.com',
          tokenType: 'Bearer',
        ),
      );
      when(mockClient.setRoomStateWithKey(any, any, any, any))
          .thenAnswer((_) async => 'event_id');
      soundService.httpPostForTest = (client, url, {headers, body}) async =>
          http.Response(
            jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'lk_token'}),
            200,
          );
      soundService.cachedLivekitServiceUrlForTest = 'https://lk-jwt.example.com';
      final mockRoom = setupMockRoom();
      when(mockRoom.isDirectChat).thenReturn(false);

      await soundService.joinCall('!room:example.com');
      fakeRingtone.userJoinedCalls = 0;

      await soundService.leaveCall();

      expect(soundService.callState, KoheraCallState.idle);
      expect(fakeRingtone.userLeftCalls, 1);
    });

    test('no join sound on failed connect', () async {
      final fakeRoom = FakeLiveKitRoom()..throwOnConnect = true;
      soundService.roomFactoryForTest = ({roomOptions}) => fakeRoom;
      when(mockClient.requestOpenIdToken(any, any)).thenAnswer(
        (_) async => OpenIdCredentials(
          accessToken: 't',
          expiresIn: 3600,
          matrixServerName: 'example.com',
          tokenType: 'Bearer',
        ),
      );
      when(mockClient.setRoomStateWithKey(any, any, any, any))
          .thenAnswer((_) async => 'event_id');
      soundService.httpPostForTest = (client, url, {headers, body}) async =>
          http.Response(
            jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'lk_token'}),
            200,
          );
      soundService.cachedLivekitServiceUrlForTest = 'https://lk-jwt.example.com';
      setupMockRoom();

      await soundService.joinCall('!room:example.com');

      expect(soundService.callState, KoheraCallState.failed);
      expect(fakeRingtone.userJoinedCalls, 0);
      expect(fakeRingtone.userLeftCalls, 0);
    });
  });
}

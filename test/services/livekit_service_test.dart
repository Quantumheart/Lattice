import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/features/calling/models/call_state.dart';
import 'package:lattice/features/calling/services/livekit_service.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>()])
import 'livekit_service_test.mocks.dart';
import 'call_test_helpers.dart';

void main() {
  late MockClient mockClient;
  late LiveKitService service;
  late int changedCount;

  final openIdCredentials = OpenIdCredentials(
    accessToken: 'token123',
    expiresIn: 3600,
    matrixServerName: 'example.com',
    tokenType: 'Bearer',
  );

  setUp(() {
    mockClient = MockClient();
    when(mockClient.userID).thenReturn('@user:example.com');
    when(mockClient.deviceID).thenReturn('DEVICE1');
    changedCount = 0;
    service = LiveKitService(
      client: mockClient,
      onChanged: () => changedCount++,
    );
  });

  tearDown(() {
    service.dispose();
  });

  Future<FakeLiveKitRoom> setupConnectedService({
    String serviceUrl = 'https://lk.example.com',
    String alias = '!room:example.com',
    String jwt = 'jwt-token',
    String livekitUrl = 'wss://lk.example.com',
  }) async {
    when(mockClient.requestOpenIdToken(any, any))
        .thenAnswer((_) async => openIdCredentials);

    service.httpPostForTest = (client, url, {headers, body}) async {
      return http.Response(
        jsonEncode({'url': livekitUrl, 'jwt': jwt}),
        200,
      );
    };

    final fakeRoom = FakeLiveKitRoom();
    service.roomFactoryForTest = () => fakeRoom;

    await service.connectLiveKit(
      livekitServiceUrl: serviceUrl,
      livekitAlias: alias,
      currentState: () => LatticeCallState.joining,
    );

    changedCount = 0;
    return fakeRoom;
  }

  // ── initial state ──────────────────────────────────────────

  group('initial state', () {
    test('livekitRoom is null', () {
      expect(service.livekitRoom, isNull);
    });

    test('participants is empty', () {
      expect(service.participants, isEmpty);
    });

    test('mic is disabled', () {
      expect(service.isMicEnabled, isFalse);
    });

    test('camera is disabled', () {
      expect(service.isCameraEnabled, isFalse);
    });

    test('screenshare is disabled', () {
      expect(service.isScreenShareEnabled, isFalse);
    });

    test('activeSpeakers is empty', () {
      expect(service.activeSpeakers, isEmpty);
    });

    test('cachedLivekitServiceUrl is null', () {
      expect(service.cachedLivekitServiceUrl, isNull);
    });

    test('allParticipants returns empty when room null', () {
      expect(service.allParticipants(activeCallRoomId: null), isEmpty);
    });
  });

  // ── connectLiveKit ─────────────────────────────────────────

  group('connectLiveKit', () {
    test('full flow connects room, enables mic, subscribes events', () async {
      final fakeRoom = await setupConnectedService();

      expect(service.livekitRoom, isNotNull);
      expect(fakeRoom.connected, isTrue);
      expect(service.isMicEnabled, isTrue);
      expect(fakeRoom.localParticipantFake!.micEnabled, isTrue);
      expect(fakeRoom.listener, isNotNull);
    });

    test('aborts after token fetch if state changed', () async {
      when(mockClient.requestOpenIdToken(any, any))
          .thenAnswer((_) async => openIdCredentials);

      service.httpPostForTest = (client, url, {headers, body}) async {
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'jwt'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      var callCount = 0;
      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () {
          callCount++;
          return callCount <= 1
              ? LatticeCallState.idle
              : LatticeCallState.joining;
        },
      );

      expect(service.livekitRoom, isNull);
      expect(fakeRoom.connected, isFalse);
    });

    test('aborts after room.connect if state changed and cleans up', () async {
      when(mockClient.requestOpenIdToken(any, any))
          .thenAnswer((_) async => openIdCredentials);

      service.httpPostForTest = (client, url, {headers, body}) async {
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'jwt'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      var callCount = 0;
      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () {
          callCount++;
          return callCount <= 1
              ? LatticeCallState.joining
              : LatticeCallState.idle;
        },
      );

      expect(service.livekitRoom, isNull);
      expect(fakeRoom.disconnected, isTrue);
      expect(fakeRoom.disposed, isTrue);
    });

    test('uses jwt field from response', () async {
      when(mockClient.requestOpenIdToken(any, any))
          .thenAnswer((_) async => openIdCredentials);

      service.httpPostForTest = (client, url, {headers, body}) async {
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'my-jwt-token'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(fakeRoom.connected, isTrue);
    });

    test('falls back to token field when jwt missing', () async {
      when(mockClient.requestOpenIdToken(any, any))
          .thenAnswer((_) async => openIdCredentials);

      service.httpPostForTest = (client, url, {headers, body}) async {
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'token': 'fallback-tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(fakeRoom.connected, isTrue);
    });

    test('throws on non-200 response', () async {
      when(mockClient.requestOpenIdToken(any, any))
          .thenAnswer((_) async => openIdCredentials);

      service.httpPostForTest = (client, url, {headers, body}) async {
        return http.Response('Unauthorized', 401);
      };

      expect(
        () => service.connectLiveKit(
          livekitServiceUrl: 'https://lk.example.com',
          livekitAlias: '!room:example.com',
          currentState: () => LatticeCallState.joining,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('401'),
        )),
      );
    });

    test('sends correct OpenID payload structure', () async {
      when(mockClient.requestOpenIdToken(any, any))
          .thenAnswer((_) async => openIdCredentials);

      Map<String, dynamic>? capturedBody;
      service.httpPostForTest = (client, url, {headers, body}) async {
        if (body is List<int>) {
          capturedBody = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        }
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(capturedBody, isNotNull);
      expect(capturedBody!['room'], '!room:example.com');
      expect(capturedBody!['device_id'], 'DEVICE1');
      final openId = capturedBody!['openid_token'] as Map<String, dynamic>;
      expect(openId['access_token'], 'token123');
      expect(openId['token_type'], 'Bearer');
      expect(openId['matrix_server_name'], 'example.com');
      expect(openId['expires_in'], 3600);
    });
  });

  // ── redirect following ─────────────────────────────────────

  group('redirect following', () {
    setUp(() {
      when(mockClient.requestOpenIdToken(any, any))
          .thenAnswer((_) async => openIdCredentials);
    });

    test('follows 301 redirect', () async {
      var requestCount = 0;
      service.httpPostForTest = (client, url, {headers, body}) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response('', 301,
              headers: {'location': 'https://redirect.example.com/sfu/get'});
        }
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(requestCount, 2);
      expect(fakeRoom.connected, isTrue);
    });

    test('follows 302 redirect', () async {
      var requestCount = 0;
      service.httpPostForTest = (client, url, {headers, body}) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response('', 302,
              headers: {'location': 'https://other.example.com/sfu/get'});
        }
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(requestCount, 2);
    });

    test('follows 307 redirect', () async {
      var requestCount = 0;
      service.httpPostForTest = (client, url, {headers, body}) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response('', 307,
              headers: {'location': 'https://other.example.com/sfu/get'});
        }
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(requestCount, 2);
    });

    test('follows chained redirects', () async {
      var requestCount = 0;
      service.httpPostForTest = (client, url, {headers, body}) async {
        requestCount++;
        if (requestCount <= 3) {
          return http.Response('', 302,
              headers: {'location': 'https://hop$requestCount.example.com/'});
        }
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(requestCount, 4);
    });

    test('throws on more than 6 redirects', () async {
      service.httpPostForTest = (client, url, {headers, body}) async {
        return http.Response('', 302,
            headers: {'location': 'https://loop.example.com/'});
      };

      expect(
        () => service.connectLiveKit(
          livekitServiceUrl: 'https://lk.example.com',
          livekitAlias: '!room:example.com',
          currentState: () => LatticeCallState.joining,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Too many redirects'),
        )),
      );
    });

    test('returns response when redirect has no location header', () async {
      service.httpPostForTest = (client, url, {headers, body}) async {
        return http.Response('', 302);
      };

      expect(
        () => service.connectLiveKit(
          livekitServiceUrl: 'https://lk.example.com',
          livekitAlias: '!room:example.com',
          currentState: () => LatticeCallState.joining,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('302'),
        )),
      );
    });

    test('resolves relative redirect URLs', () async {
      var requestCount = 0;
      Uri? secondUrl;
      service.httpPostForTest = (client, url, {headers, body}) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response('', 302,
              headers: {'location': '/new-path/sfu/get'});
        }
        secondUrl = url;
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(secondUrl?.host, 'lk.example.com');
      expect(secondUrl?.path, '/new-path/sfu/get');
    });
  });

  // ── track toggles (mic) ────────────────────────────────────

  group('track toggles (mic)', () {
    test('toggles mic off from enabled state', () async {
      final fakeRoom = await setupConnectedService();

      await service.toggleMicrophone();

      expect(service.isMicEnabled, isFalse);
      expect(fakeRoom.localParticipantFake!.micEnabled, isFalse);
      expect(changedCount, 1);
    });

    test('toggles mic back on', () async {
      final fakeRoom = await setupConnectedService();

      await service.toggleMicrophone();
      changedCount = 0;
      await service.toggleMicrophone();

      expect(service.isMicEnabled, isTrue);
      expect(fakeRoom.localParticipantFake!.micEnabled, isTrue);
      expect(changedCount, 1);
    });

    test('rolls back on error and calls onChanged twice', () async {
      final fakeRoom = await setupConnectedService();
      fakeRoom.localParticipantFake!.throwOnToggle = true;

      await service.toggleMicrophone();

      expect(service.isMicEnabled, isTrue);
      expect(changedCount, 2);
    });

    test('no-op when localParticipant is null', () async {
      final fakeRoom = await setupConnectedService();
      fakeRoom.localParticipantFake = null;

      await service.toggleMicrophone();

      expect(changedCount, 0);
    });

    test('no-op when room is null', () async {
      await service.toggleMicrophone();
      expect(changedCount, 0);
    });
  });

  // ── track toggles (camera) ─────────────────────────────────

  group('track toggles (camera)', () {
    test('toggles camera on', () async {
      final fakeRoom = await setupConnectedService();

      await service.toggleCamera();

      expect(service.isCameraEnabled, isTrue);
      expect(fakeRoom.localParticipantFake!.cameraEnabled, isTrue);
      expect(changedCount, 1);
    });

    test('rolls back on error', () async {
      final fakeRoom = await setupConnectedService();
      fakeRoom.localParticipantFake!.throwOnToggle = true;

      await service.toggleCamera();

      expect(service.isCameraEnabled, isFalse);
      expect(changedCount, 2);
    });

    test('no-op when localParticipant is null', () async {
      final fakeRoom = await setupConnectedService();
      fakeRoom.localParticipantFake = null;

      await service.toggleCamera();
      expect(changedCount, 0);
    });
  });

  // ── track toggles (screenshare) ────────────────────────────

  group('track toggles (screenshare)', () {
    test('toggles screenshare on', () async {
      final fakeRoom = await setupConnectedService();

      await service.toggleScreenShare();

      expect(service.isScreenShareEnabled, isTrue);
      expect(fakeRoom.localParticipantFake!.screenShareEnabled, isTrue);
      expect(changedCount, 1);
    });

    test('rolls back on error', () async {
      final fakeRoom = await setupConnectedService();
      fakeRoom.localParticipantFake!.throwOnToggle = true;

      await service.toggleScreenShare();

      expect(service.isScreenShareEnabled, isFalse);
      expect(changedCount, 2);
    });

    test('no-op when localParticipant is null', () async {
      final fakeRoom = await setupConnectedService();
      fakeRoom.localParticipantFake = null;

      await service.toggleScreenShare();
      expect(changedCount, 0);
    });
  });

  // ── participant aggregation ────────────────────────────────

  group('participant aggregation', () {
    test('empty when room null', () {
      expect(service.allParticipants(activeCallRoomId: '!r:x'), isEmpty);
    });

    test('includes local participant', () async {
      await setupConnectedService();

      final participants = service.allParticipants(activeCallRoomId: null);
      expect(participants, hasLength(1));
      expect(participants.first.isLocal, isTrue);
    });

    test('includes remote participants after sync', () async {
      final fakeRoom = await setupConnectedService();
      final remote = FakeRemoteParticipant(
        identity: '@bob:example.com:BOBDEV',
        name: 'Bob',
      );
      fakeRoom.remoteParticipantsMap['remote1'] = remote;

      fakeRoom.listener!.fire(livekit.ParticipantConnectedEvent(
        participant: remote,
      ));

      final participants = service.allParticipants(activeCallRoomId: null);
      expect(participants, hasLength(2));
      expect(participants.last.id, '@bob:example.com');
    });

    test('caches participant list (same object)', () async {
      await setupConnectedService();

      final first = service.allParticipants(activeCallRoomId: null);
      final second = service.allParticipants(activeCallRoomId: null);
      expect(identical(first, second), isTrue);
    });

    test('invalidates cache on dirty flag', () async {
      final fakeRoom = await setupConnectedService();

      final first = service.allParticipants(activeCallRoomId: null);

      fakeRoom.listener!.fire(livekit.TrackMutedEvent(
        participant: fakeRoom.localParticipantFake!,
        publication: FakeTrackPublication(),
      ));

      final second = service.allParticipants(activeCallRoomId: null);
      expect(identical(first, second), isFalse);
    });

    test('invalidates cache on roomId change', () async {
      await setupConnectedService();

      final first = service.allParticipants(activeCallRoomId: '!a:x');
      final second = service.allParticipants(activeCallRoomId: '!b:x');
      expect(identical(first, second), isFalse);
    });

    test('resolves avatar from Matrix room', () async {
      await setupConnectedService();

      final matrixRoom = MockRoom();
      final avatarUri = Uri.parse('mxc://example.com/avatar');
      final fakeUser = FakeUser(avatarUrl: avatarUri);
      when(mockClient.getRoomById('!r:x')).thenReturn(matrixRoom);
      when(matrixRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(fakeUser);

      final participants = service.allParticipants(activeCallRoomId: '!r:x');
      expect(participants.first.avatarUrl, avatarUri);
    });

    test('handles null roomId gracefully', () async {
      await setupConnectedService();

      final participants = service.allParticipants(activeCallRoomId: null);
      expect(participants.first.avatarUrl, isNull);
    });
  });

  // ── cleanupLiveKit ─────────────────────────────────────────

  group('cleanupLiveKit', () {
    test('resets all state', () async {
      await setupConnectedService();

      await service.cleanupLiveKit();

      expect(service.livekitRoom, isNull);
      expect(service.participants, isEmpty);
      expect(service.activeSpeakers, isEmpty);
      expect(service.isMicEnabled, isFalse);
      expect(service.isCameraEnabled, isFalse);
      expect(service.isScreenShareEnabled, isFalse);
      expect(service.allParticipants(activeCallRoomId: null), isEmpty);
    });

    test('disposes listener, disconnects, and disposes room', () async {
      final fakeRoom = await setupConnectedService();

      await service.cleanupLiveKit();

      expect(fakeRoom.disconnected, isTrue);
      expect(fakeRoom.disposed, isTrue);
    });

    test('handles listener dispose error gracefully', () async {
      final fakeRoom = await setupConnectedService();
      fakeRoom.listener!.throwOnDispose = true;

      await service.cleanupLiveKit();

      expect(service.livekitRoom, isNull);
      expect(fakeRoom.disconnected, isTrue);
    });

    test('handles room disconnect error gracefully', () async {
      final fakeRoom = await setupConnectedService();
      fakeRoom.throwOnDisconnect = true;

      await service.cleanupLiveKit();

      expect(service.livekitRoom, isNull);
      expect(fakeRoom.disposed, isTrue);
    });

    test('handles room dispose error gracefully', () async {
      final fakeRoom = await setupConnectedService();
      fakeRoom.throwOnDispose = true;

      await service.cleanupLiveKit();

      expect(service.livekitRoom, isNull);
    });

    test('safe when not connected', () async {
      await service.cleanupLiveKit();

      expect(service.livekitRoom, isNull);
    });
  });

  // ── well-known ─────────────────────────────────────────────

  group('well-known', () {
    test('fetches and caches URL', () async {
      when(mockClient.getWellknown()).thenAnswer((_) async =>
          DiscoveryInformation(
            mHomeserver: HomeserverInformation(
                baseUrl: Uri.parse('https://example.com')),
            additionalProperties: {
              'org.matrix.msc4143.rtc_foci': [
                {
                  'type': 'livekit',
                  'livekit_service_url': 'https://lk.example.com',
                },
              ],
            },
          ));

      await service.fetchWellKnownLiveKit();

      expect(service.cachedLivekitServiceUrl, 'https://lk.example.com');
    });

    test('returns cached on subsequent access', () async {
      when(mockClient.getWellknown()).thenAnswer((_) async =>
          DiscoveryInformation(
            mHomeserver: HomeserverInformation(
                baseUrl: Uri.parse('https://example.com')),
            additionalProperties: {
              'org.matrix.msc4143.rtc_foci': [
                {
                  'type': 'livekit',
                  'livekit_service_url': 'https://lk.example.com',
                },
              ],
            },
          ));

      await service.fetchWellKnownLiveKit();
      final first = service.cachedLivekitServiceUrl;
      final second = service.cachedLivekitServiceUrl;

      expect(first, 'https://lk.example.com');
      expect(second, 'https://lk.example.com');
    });

    test('returns null for empty foci list', () async {
      when(mockClient.getWellknown()).thenAnswer((_) async =>
          DiscoveryInformation(
            mHomeserver: HomeserverInformation(
                baseUrl: Uri.parse('https://example.com')),
            additionalProperties: {
              'org.matrix.msc4143.rtc_foci': <dynamic>[],
            },
          ));

      await service.fetchWellKnownLiveKit();

      expect(service.cachedLivekitServiceUrl, isNull);
    });

    test('returns null for missing foci list', () async {
      when(mockClient.getWellknown()).thenAnswer((_) async =>
          DiscoveryInformation(
            mHomeserver: HomeserverInformation(
                baseUrl: Uri.parse('https://example.com')),
          ));

      await service.fetchWellKnownLiveKit();

      expect(service.cachedLivekitServiceUrl, isNull);
    });

    test('skips non-livekit entries', () async {
      when(mockClient.getWellknown()).thenAnswer((_) async =>
          DiscoveryInformation(
            mHomeserver: HomeserverInformation(
                baseUrl: Uri.parse('https://example.com')),
            additionalProperties: {
              'org.matrix.msc4143.rtc_foci': [
                {'type': 'jitsi', 'url': 'https://jitsi.example.com'},
              ],
            },
          ));

      await service.fetchWellKnownLiveKit();

      expect(service.cachedLivekitServiceUrl, isNull);
    });

    test('handles getWellknown throwing', () async {
      when(mockClient.getWellknown()).thenThrow(Exception('network error'));

      await service.fetchWellKnownLiveKit();

      expect(service.cachedLivekitServiceUrl, isNull);
    });

    test('uses first valid livekit entry', () async {
      when(mockClient.getWellknown()).thenAnswer((_) async =>
          DiscoveryInformation(
            mHomeserver: HomeserverInformation(
                baseUrl: Uri.parse('https://example.com')),
            additionalProperties: {
              'org.matrix.msc4143.rtc_foci': [
                {
                  'type': 'livekit',
                  'livekit_service_url': 'https://first.example.com',
                },
                {
                  'type': 'livekit',
                  'livekit_service_url': 'https://second.example.com',
                },
              ],
            },
          ));

      await service.fetchWellKnownLiveKit();

      expect(service.cachedLivekitServiceUrl, 'https://first.example.com');
    });

    test('skips livekit entry without URL', () async {
      when(mockClient.getWellknown()).thenAnswer((_) async =>
          DiscoveryInformation(
            mHomeserver: HomeserverInformation(
                baseUrl: Uri.parse('https://example.com')),
            additionalProperties: {
              'org.matrix.msc4143.rtc_foci': [
                {'type': 'livekit'},
                {
                  'type': 'livekit',
                  'livekit_service_url': 'https://valid.example.com',
                },
              ],
            },
          ));

      await service.fetchWellKnownLiveKit();

      expect(service.cachedLivekitServiceUrl, 'https://valid.example.com');
    });

    test('test setter sets and clears cache', () {
      service.cachedLivekitServiceUrlForTest = 'https://test.example.com';
      expect(service.cachedLivekitServiceUrl, 'https://test.example.com');

      service.cachedLivekitServiceUrlForTest = null;
      expect(service.cachedLivekitServiceUrl, isNull);
    });
  });

  // ── LiveKit events ─────────────────────────────────────────

  group('LiveKit events', () {
    test('RoomReconnecting emits to stream', () async {
      final fakeRoom = await setupConnectedService();

      final events = <LiveKitConnectionEvent>[];
      service.connectionEvents.listen(events.add);

      fakeRoom.listener!.fire(const livekit.RoomReconnectingEvent());

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first, isA<LiveKitReconnecting>());
    });

    test('RoomReconnected emits to stream', () async {
      final fakeRoom = await setupConnectedService();

      final events = <LiveKitConnectionEvent>[];
      service.connectionEvents.listen(events.add);

      fakeRoom.listener!.fire(const livekit.RoomReconnectedEvent());

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first, isA<LiveKitReconnected>());
    });

    test('RoomDisconnected emits to stream', () async {
      final fakeRoom = await setupConnectedService();

      final events = <LiveKitConnectionEvent>[];
      service.connectionEvents.listen(events.add);

      fakeRoom.listener!.fire(livekit.RoomDisconnectedEvent());

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first, isA<LiveKitDisconnected>());
    });

    test('ParticipantConnected syncs and notifies', () async {
      final fakeRoom = await setupConnectedService();
      final remote = FakeRemoteParticipant(identity: '@bob:example.com');
      fakeRoom.remoteParticipantsMap['r1'] = remote;

      fakeRoom.listener!.fire(livekit.ParticipantConnectedEvent(
        participant: remote,
      ));

      expect(service.participants, hasLength(1));
      expect(changedCount, 1);
    });

    test('ParticipantDisconnected syncs and notifies', () async {
      final fakeRoom = await setupConnectedService();
      final remote = FakeRemoteParticipant(identity: '@bob:example.com');

      fakeRoom.listener!.fire(livekit.ParticipantDisconnectedEvent(
        participant: remote,
      ));

      expect(changedCount, 1);
    });

    test('ActiveSpeakersChanged updates speakers', () async {
      final fakeRoom = await setupConnectedService();

      fakeRoom.listener!.fire(livekit.ActiveSpeakersChangedEvent(
        speakers: [fakeRoom.localParticipantFake!],
      ));

      expect(service.activeSpeakers, hasLength(1));
      expect(changedCount, 1);
    });

    test('TrackMuted invalidates and notifies', () async {
      final fakeRoom = await setupConnectedService();

      fakeRoom.listener!.fire(livekit.TrackMutedEvent(
        participant: fakeRoom.localParticipantFake!,
        publication: FakeTrackPublication(),
      ));

      expect(changedCount, 1);
    });

    test('TrackUnmuted invalidates and notifies', () async {
      final fakeRoom = await setupConnectedService();

      fakeRoom.listener!.fire(livekit.TrackUnmutedEvent(
        participant: fakeRoom.localParticipantFake!,
        publication: FakeTrackPublication(),
      ));

      expect(changedCount, 1);
    });

    test('TrackSubscribed invalidates and notifies', () async {
      final fakeRoom = await setupConnectedService();
      final remote = FakeRemoteParticipant();

      fakeRoom.listener!.fire(livekit.TrackSubscribedEvent(
        participant: remote,
        publication: FakeRemoteTrackPublication(),
        track: FakeTrack(),
      ));

      expect(changedCount, 1);
    });

    test('TrackUnsubscribed invalidates and notifies', () async {
      final fakeRoom = await setupConnectedService();
      final remote = FakeRemoteParticipant();

      fakeRoom.listener!.fire(livekit.TrackUnsubscribedEvent(
        participant: remote,
        publication: FakeRemoteTrackPublication(),
        track: FakeTrack(),
      ));

      expect(changedCount, 1);
    });

    test('LocalTrackPublished invalidates and notifies', () async {
      final fakeRoom = await setupConnectedService();

      fakeRoom.listener!.fire(livekit.LocalTrackPublishedEvent(
        participant: fakeRoom.localParticipantFake!,
        publication: FakeLocalTrackPublication(),
      ));

      expect(changedCount, 1);
    });

    test('LocalTrackUnpublished invalidates and notifies', () async {
      final fakeRoom = await setupConnectedService();

      fakeRoom.listener!.fire(livekit.LocalTrackUnpublishedEvent(
        participant: fakeRoom.localParticipantFake!,
        publication: FakeLocalTrackPublication(),
      ));

      expect(changedCount, 1);
    });
  });

  // ── _buildServiceUrl ───────────────────────────────────────

  group('_buildServiceUrl (via connectLiveKit URL)', () {
    setUp(() {
      when(mockClient.requestOpenIdToken(any, any))
          .thenAnswer((_) async => openIdCredentials);
    });

    test('trailing slash does not produce double slash', () async {
      Uri? capturedUrl;
      service.httpPostForTest = (client, url, {headers, body}) async {
        capturedUrl = url;
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com/',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(capturedUrl?.path, '/sfu/get');
      expect(capturedUrl.toString(), isNot(contains('//sfu')));
    });

    test('no trailing slash adds slash', () async {
      Uri? capturedUrl;
      service.httpPostForTest = (client, url, {headers, body}) async {
        capturedUrl = url;
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(capturedUrl?.path, '/sfu/get');
    });
  });

  // ── updateClient ───────────────────────────────────────────

  group('updateClient', () {
    test('new client reference used for subsequent operations', () async {
      final newClient = MockClient();
      when(newClient.userID).thenReturn('@newuser:example.com');
      when(newClient.deviceID).thenReturn('DEVICE2');
      when(newClient.requestOpenIdToken(any, any))
          .thenAnswer((_) async => openIdCredentials);

      service.updateClient(newClient);

      Map<String, dynamic>? capturedBody;
      service.httpPostForTest = (client, url, {headers, body}) async {
        if (body is List<int>) {
          capturedBody = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        }
        return http.Response(
          jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'tok'}),
          200,
        );
      };

      final fakeRoom = FakeLiveKitRoom();
      service.roomFactoryForTest = () => fakeRoom;

      await service.connectLiveKit(
        livekitServiceUrl: 'https://lk.example.com',
        livekitAlias: '!room:example.com',
        currentState: () => LatticeCallState.joining,
      );

      expect(capturedBody!['device_id'], 'DEVICE2');
      verify(newClient.requestOpenIdToken(any, any)).called(1);
    });
  });

  // ── dispose ────────────────────────────────────────────────

  group('dispose', () {
    test('closes connectionEvent stream', () async {
      final events = <LiveKitConnectionEvent>[];
      final sub = service.connectionEvents.listen(events.add);

      service.dispose();

      await expectLater(service.connectionEvents, emitsDone);
      await sub.cancel();
    });
  });
}

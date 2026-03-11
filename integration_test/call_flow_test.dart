import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/calling/screens/call_pane.dart';
import 'package:lattice/features/calling/widgets/incoming_call_overlay.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../test/services/call_test_helpers.dart';
import 'helpers/mocks.dart';
import 'helpers/test_app.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _roomId = '!callroom:example.com';
const _myUserId = '@me:example.com';
const _myDeviceId = 'DEVICE1';

// ── Test Harness ─────────────────────────────────────────────────────────────

class _CallTestHarness {
  late MockClient mockClient;
  late MockRoom mockRoom;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;
  late CallService callService;
  late CachedStreamController<SyncUpdate> syncController;
  late CachedStreamController<Event> timelineEventController;
  late CachedStreamController<({String roomId, StrippedStateEvent state})>
      roomStateController;
  late FakeLiveKitRoom fakeLiveKitRoom;

  void setUp() {
    mockClient = MockClient();
    mockRoom = MockRoom();
    mockStorage = MockFlutterSecureStorage();
    syncController = CachedStreamController<SyncUpdate>();
    timelineEventController = CachedStreamController<Event>();
    roomStateController =
        CachedStreamController<({String roomId, StrippedStateEvent state})>();

    stubLoggedInClient(mockClient, syncController);
    when(mockClient.userID).thenReturn(_myUserId);
    when(mockClient.deviceID).thenReturn(_myDeviceId);
    when(mockClient.rooms).thenReturn([mockRoom]);
    when(mockClient.getRoomById(_roomId)).thenReturn(mockRoom);
    when(mockClient.onTimelineEvent).thenReturn(timelineEventController);
    when(mockClient.onRoomState).thenReturn(roomStateController);
    when(mockClient.getProfileFromUserId(any)).thenAnswer(
      (_) async => Profile(userId: '@unknown:example.com'),
    );
    when(mockClient.getWellknown()).thenAnswer(
      (_) async => DiscoveryInformation(
        mHomeserver: HomeserverInformation(
          baseUrl: Uri.parse('https://example.com'),
        ),
        additionalProperties: {
          'org.matrix.msc4143.rtc_foci': [
            {
              'type': 'livekit',
              'livekit_service_url': 'https://lk-jwt.example.com',
            },
          ],
        },
      ),
    );

    when(mockRoom.id).thenReturn(_roomId);
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Call Room');
    when(mockRoom.canonicalAlias).thenReturn('#callroom:example.com');
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.states).thenReturn({});
    when(mockRoom.isDirectChat).thenReturn(true);
    when(mockRoom.encrypted).thenReturn(false);
    when(mockRoom.summary).thenReturn(
      RoomSummary.fromJson({'m.joined_member_count': 2}),
    );
    when(mockRoom.pinnedEventIds).thenReturn([]);
    when(mockRoom.typingUsers).thenReturn([]);
    when(mockRoom.notificationCount).thenReturn(0);
    when(mockRoom.lastEvent).thenReturn(null);
    when(mockRoom.avatar).thenReturn(null);
    when(mockRoom.canChangeStateEvent(any)).thenReturn(true);
    when(mockRoom.receiptState).thenReturn(LatestReceiptState.empty());
    when(mockRoom.unsafeGetUserFromMemoryOrFallback(any)).thenAnswer(
      (invocation) => User(
        invocation.positionalArguments[0] as String,
        room: mockRoom,
      ),
    );
    when(mockRoom.sendEvent(any, type: anyNamed('type')))
        .thenAnswer((_) async => 'event_id');
    when(mockClient.setRoomStateWithKey(any, any, any, any))
        .thenAnswer((_) async => 'event_id');
    when(mockClient.requestOpenIdToken(any, any)).thenAnswer(
      (_) async => OpenIdCredentials(
        accessToken: 'openid_token',
        expiresIn: 3600,
        matrixServerName: 'example.com',
        tokenType: 'Bearer',
      ),
    );

    matrixService = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
    matrixService.isLoggedInForTest = true;

    clientManager = ClientManager(
      storage: mockStorage,
      serviceFactory: FixedServiceFactory(matrixService),
    );

    callService = CallService(client: mockClient);
    _setupLiveKitFakes();
  }

  void _setupLiveKitFakes() {
    fakeLiveKitRoom = FakeLiveKitRoom();
    callService.roomFactoryForTest = () => fakeLiveKitRoom;
    callService.cachedLivekitServiceUrlForTest = 'https://lk-jwt.example.com';
    callService.httpPostForTest = (client, url, {headers, body}) async {
      return http.Response(
        jsonEncode({'url': 'wss://lk.example.com', 'jwt': 'lk_token'}),
        200,
      );
    };
  }

  Widget buildCallApp({String? initialLocation}) {
    final router = GoRouter(
      initialLocation: initialLocation ?? '/rooms/$_roomId/call',
      routes: [
        GoRoute(
          path: '/',
          name: Routes.home,
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('Home')),
          ),
        ),
        GoRoute(
          path: '/rooms/:roomId',
          name: Routes.room,
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text('Room ${state.pathParameters['roomId']}'),
            ),
          ),
          routes: [
            GoRoute(
              path: 'call',
              name: Routes.call,
              builder: (_, __) => const Scaffold(body: CallPane()),
            ),
          ],
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
        ChangeNotifierProvider<CallService>.value(value: callService),
        ChangeNotifierProvider(create: (_) => PreferencesService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Widget buildOverlayApp() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          name: Routes.home,
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('Home')),
          ),
        ),
        GoRoute(
          path: '/rooms/:roomId',
          name: Routes.room,
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text('Room ${state.pathParameters['roomId']}'),
            ),
          ),
          routes: [
            GoRoute(
              path: 'call',
              name: Routes.call,
              builder: (_, __) => const Scaffold(body: CallPane()),
            ),
          ],
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
        ChangeNotifierProvider<CallService>.value(value: callService),
        ChangeNotifierProvider(create: (_) => PreferencesService()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => IncomingCallOverlay(
          router: router,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _CallTestHarness h;

  setUp(() {
    h = _CallTestHarness()..setUp();
  });

  // ── Group 1: Outgoing call flow ───────────────────────────────────────────

  group('Outgoing call flow', () {
    testWidgets('initiateCall shows ringing UI with cancel button',
        (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.initiateCall(_roomId);
      await tester.pump();

      expect(h.callService.callState, LatticeCallState.ringingOutgoing);
      expect(find.textContaining('Calling'), findsOneWidget);
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
    });

    testWidgets('cancel outgoing call via UI returns to idle', (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.initiateCall(_roomId);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.call_end_rounded));
      await tester.pumpAndSettle();

      expect(h.callService.callState, LatticeCallState.idle);
    });

    testWidgets('joinCall transitions to connected with control bar',
        (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.joinCall(_roomId);
      await tester.pumpAndSettle();

      expect(h.callService.callState, LatticeCallState.connected);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);
    });

    testWidgets('hang up via control bar returns to idle', (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.joinCall(_roomId);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.call_end));
      await tester.pumpAndSettle();

      expect(h.callService.callState, LatticeCallState.idle);
    });
  });

  // ── Group 2: Incoming call flow ───────────────────────────────────────────

  group('Incoming call flow', () {
    testWidgets('incoming invite shows overlay with 3 FABs', (tester) async {
      h.callService.init();
      await tester.pumpWidget(h.buildOverlayApp());
      await tester.pumpAndSettle();

      _injectCallInvite(h);
      await tester.pump();

      expect(h.callService.callState, LatticeCallState.ringingIncoming);
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
      expect(find.byIcon(Icons.call_rounded), findsOneWidget);
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
    });

    testWidgets('decline incoming dismisses overlay', (tester) async {
      h.callService.init();
      await tester.pumpWidget(h.buildOverlayApp());
      await tester.pumpAndSettle();

      _injectCallInvite(h);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.call_end_rounded));
      await tester.pumpAndSettle();

      expect(h.callService.callState, LatticeCallState.idle);
      expect(find.byIcon(Icons.call_rounded), findsNothing);
    });

    testWidgets('accept incoming audio navigates to call and connects',
        (tester) async {
      h.callService.init();
      await tester.pumpWidget(h.buildOverlayApp());
      await tester.pumpAndSettle();

      _injectCallInvite(h);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.call_rounded));
      await tester.pump();

      expect(
        h.callService.callState,
        LatticeCallState.connected,
      );
    });
  });

  // ── Group 3: Connected call controls ──────────────────────────────────────

  group('Connected call controls', () {
    testWidgets('toggle mic changes tooltip', (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.joinCall(_roomId);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Mute'), findsOneWidget);

      await tester.tap(find.byTooltip('Mute'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Unmute'), findsOneWidget);

      await tester.tap(find.byTooltip('Unmute'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Mute'), findsOneWidget);
    });

    testWidgets('toggle camera changes tooltip', (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.joinCall(_roomId);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Turn on camera'), findsOneWidget);

      await tester.tap(find.byTooltip('Turn on camera'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Turn off camera'), findsOneWidget);
    });

    testWidgets('participant count updates when remote joins', (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.joinCall(_roomId);
      await tester.pumpAndSettle();

      expect(find.text('1 participant'), findsOneWidget);

      final fakeRemote = FakeRemoteParticipant(
        identity: '@bob:example.com',
        name: 'Bob',
      );
      h.fakeLiveKitRoom.remoteParticipantsMap['bob'] = fakeRemote;
      h.fakeLiveKitRoom.listener!.fire(
        livekit.ParticipantConnectedEvent(participant: fakeRemote),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 participants'), findsOneWidget);
    });
  });

  // ── Group 4: LiveKit connection events ────────────────────────────────────

  group('LiveKit connection events', () {
    testWidgets('reconnecting shows reconnecting view', (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.joinCall(_roomId);
      await tester.pumpAndSettle();

      h.fakeLiveKitRoom.listener!
          .fire(const livekit.RoomReconnectingEvent());
      await tester.pump();
      await tester.pump();

      expect(find.text('Reconnecting...'), findsOneWidget);
    });

    testWidgets('reconnected returns to connected view', (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.joinCall(_roomId);
      await tester.pumpAndSettle();

      h.fakeLiveKitRoom.listener!
          .fire(const livekit.RoomReconnectingEvent());
      await tester.pump();
      await tester.pump();

      expect(find.text('Reconnecting...'), findsOneWidget);

      h.fakeLiveKitRoom.listener!
          .fire(const livekit.RoomReconnectedEvent());
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.text('Reconnecting...'), findsNothing);
    });

    testWidgets('disconnect shows failed/no-active-call state', (tester) async {
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.joinCall(_roomId);
      await tester.pumpAndSettle();

      h.fakeLiveKitRoom.listener!
          .fire(livekit.RoomDisconnectedEvent());
      await tester.pump();
      await tester.pump();

      expect(h.callService.callState, LatticeCallState.failed);
    });
  });

  // ── Group 5: Signaling edge cases ─────────────────────────────────────────

  group('Signaling edge cases', () {
    testWidgets('remote reject of outgoing call returns to idle',
        (tester) async {
      h.callService.init();
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.initiateCall(_roomId);
      await tester.pump();

      final callId = h.callService.activeCallId!;
      _injectSignalingEvent(
        h,
        type: 'm.call.reject',
        callId: callId,
      );
      await tester.pump();
      await tester.pump();

      expect(h.callService.callState, LatticeCallState.idle);
    });

    testWidgets('remote hangup during connected call ends call',
        (tester) async {
      h.callService.init();
      await tester.pumpWidget(h.buildCallApp());
      await tester.pumpAndSettle();

      await h.callService.initiateCall(_roomId);
      final callId = h.callService.activeCallId!;

      await h.callService.joinCall(_roomId);
      await tester.pumpAndSettle();

      expect(h.callService.callState, LatticeCallState.connected);

      _injectSignalingEvent(h, type: 'm.call.hangup', callId: callId);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(h.callService.callState, LatticeCallState.idle);
    });
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

void _injectCallInvite(_CallTestHarness h) {
  final callId = 'test_call_${DateTime.now().millisecondsSinceEpoch}';
  final event = Event(
    type: 'm.call.invite',
    content: {
      'call_id': callId,
      'version': 1,
      'lifetime': 60000,
      'offer': {'type': 'offer', 'sdp': ''},
      'is_video': false,
    },
    eventId: '\$invite_$callId',
    senderId: '@bob:example.com',
    originServerTs: DateTime.now(),
    room: h.mockRoom,
  );
  h.timelineEventController.add(event);
}

void _injectSignalingEvent(
  _CallTestHarness h, {
  required String type,
  required String callId,
  String senderId = '@bob:example.com',
}) {
  final event = Event(
    type: type,
    content: {'call_id': callId, 'version': 1},
    eventId: '\$evt_${Object().hashCode}',
    senderId: senderId,
    originServerTs: DateTime.now(),
    room: h.mockRoom,
  );
  h.timelineEventController.add(event);
}

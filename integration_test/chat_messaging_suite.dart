import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/screens/chat_screen.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'helpers/mocks.dart';
import 'helpers/test_app.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _roomId = '!chatroom:example.com';
const _myUserId = '@me:example.com';

// ── Helpers ──────────────────────────────────────────────────────────────────

Event makeFakeEvent({
  required Room room,
  String? eventId,
  String senderId = '@alice:example.com',
  String body = 'Hello',
  String msgtype = MessageTypes.Text,
  String type = EventTypes.Message,
  DateTime? originServerTs,
}) {
  return Event(
    type: type,
    content: {'body': body, 'msgtype': msgtype},
    eventId: eventId ?? '\$evt_${Object().hashCode}',
    senderId: senderId,
    originServerTs: originServerTs ?? DateTime(2024),
    room: room,
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  chatMessagingTests();
}

void chatMessagingTests() {
  late MockClient mockClient;
  late MockRoom mockRoom;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;
  late CachedStreamController<SyncUpdate> syncController;

  setUp(() {
    mockClient = MockClient();
    mockRoom = MockRoom();
    mockStorage = MockFlutterSecureStorage();
    syncController = CachedStreamController<SyncUpdate>();

    stubLoggedInClient(mockClient, syncController);
    when(mockClient.userID).thenReturn(_myUserId);
    when(mockClient.rooms).thenReturn([mockRoom]);
    when(mockClient.getRoomById(_roomId)).thenReturn(mockRoom);
    when(mockClient.onTimelineEvent)
        .thenReturn(CachedStreamController<Event>());
    when(mockClient.onRoomState).thenReturn(
      CachedStreamController<({String roomId, StrippedStateEvent state})>(),
    );

    when(mockRoom.id).thenReturn(_roomId);
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Chat Room');
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.summary).thenReturn(
      RoomSummary.fromJson({'m.joined_member_count': 3}),
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
  });

  // ── Test app builder ──────────────────────────────────────────────────────

  Widget buildChatIntegrationApp() {
    final router = GoRouter(
      initialLocation: '/rooms/$_roomId',
      routes: [
        GoRoute(
          path: '/rooms/:roomId',
          builder: (_, state) =>
              ChatScreen(roomId: state.pathParameters['roomId']!),
          routes: [
            GoRoute(
              path: 'details',
              name: 'room-details',
              builder: (_, __) => const Scaffold(
                body: Center(child: Text('Room Details')),
              ),
            ),
          ],
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
        ChangeNotifierProvider(
          create: (_) => CallService(client: mockClient),
        ),
        ChangeNotifierProvider(create: (_) => PreferencesService()),
        ChangeNotifierProvider(create: (_) => MediaPlaybackService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  void stubTimeline(List<Event> events) {
    final mockTimeline = MockTimeline();
    when(mockTimeline.events).thenReturn(events);
    when(mockTimeline.canRequestHistory).thenReturn(false);
    when(mockRoom.getTimeline(
      onUpdate: anyNamed('onUpdate'),
    ),).thenAnswer((_) async => mockTimeline);
  }

  void stubSendText() {
    when(mockRoom.sendTextEvent(
      any,
      inReplyTo: anyNamed('inReplyTo'),
      editEventId: anyNamed('editEventId'),
    ),).thenAnswer((_) async => r'$sent');
  }

  // ── Integration Tests ──────────────────────────────────────────────────────

  group('Chat messaging integration', () {
    testWidgets('navigate to room and send text message', (tester) async {
      stubTimeline([]);
      stubSendText();

      await tester.pumpWidget(buildChatIntegrationApp());
      await tester.pumpAndSettle();

      expect(find.text('Chat Room'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Type a message…'),
        'Hello world',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      verify(mockRoom.sendTextEvent('Hello world')).called(1);
    });

    testWidgets('empty compose bar shows mic; typing shows send',
        (tester) async {
      stubTimeline([]);

      await tester.pumpWidget(buildChatIntegrationApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Type a message…'),
        'typing...',
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
    });

    testWidgets('messages display in chat view', (tester) async {
      final events = [
        makeFakeEvent(
          room: mockRoom,
          eventId: r'$1',
          body: 'First message',
        ),
        makeFakeEvent(
          room: mockRoom,
          eventId: r'$2',
          body: 'Second message',
          senderId: '@bob:example.com',
        ),
      ];
      stubTimeline(events);

      await tester.pumpWidget(buildChatIntegrationApp());
      await tester.pumpAndSettle();

      expect(find.text('First message'), findsOneWidget);
      expect(find.text('Second message'), findsOneWidget);
    });

    testWidgets('empty room shows placeholder message', (tester) async {
      stubTimeline([]);

      await tester.pumpWidget(buildChatIntegrationApp());
      await tester.pumpAndSettle();

      expect(find.text('No messages yet.\nSay hello!'), findsOneWidget);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/chat/screens/chat_screen.dart';
import 'package:lattice/features/chat/services/media_playback_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service_test.mocks.dart' show MockFlutterSecureStorage;
import 'chat_screen_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
])

// ── Constants ─────────────────────────────────────────────────────────

const _roomId = '!test:matrix.org';
const _myUserId = '@me:matrix.org';

// ── Helpers ───────────────────────────────────────────────────────────

Event makeFakeEvent({
  required Room room,
  String? eventId,
  String senderId = '@alice:matrix.org',
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

void stubRoomDefaults(
  MockRoom mockRoom,
  MockClient mockClient, {
  String displayName = 'Test Room',
  int memberCount = 3,
  List<String> pinnedEventIds = const [],
}) {
  when(mockRoom.id).thenReturn(_roomId);
  when(mockRoom.getLocalizedDisplayname()).thenReturn(displayName);
  when(mockRoom.client).thenReturn(mockClient);
  when(mockRoom.summary).thenReturn(
    RoomSummary.fromJson({'m.joined_member_count': memberCount}),
  );
  when(mockRoom.pinnedEventIds).thenReturn(pinnedEventIds);
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
}

void stubTimeline(
  MockRoom mockRoom,
  MockTimeline mockTimeline,
  List<Event> events,
) {
  when(mockTimeline.events).thenReturn(events);
  when(mockTimeline.canRequestHistory).thenReturn(false);
  when(mockRoom.getTimeline(
    onUpdate: anyNamed('onUpdate'),
  ),).thenAnswer((_) async => mockTimeline);
}

// ── Tests ─────────────────────────────────────────────────────────────

void main() {
  late MockClient mockClient;
  late MockRoom mockRoom;
  late MockTimeline mockTimeline;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late CachedStreamController<SyncUpdate> syncController;

  setUp(() {
    mockClient = MockClient();
    mockRoom = MockRoom();
    mockTimeline = MockTimeline();
    mockStorage = MockFlutterSecureStorage();
    syncController = CachedStreamController<SyncUpdate>();

    when(mockClient.getRoomById(_roomId)).thenReturn(mockRoom);
    when(mockClient.userID).thenReturn(_myUserId);
    when(mockClient.rooms).thenReturn([mockRoom]);
    when(mockClient.onSync).thenReturn(syncController);
    when(mockClient.encryption).thenReturn(null);
    when(mockClient.homeserver).thenReturn(Uri.parse('https://matrix.org'));

    stubRoomDefaults(mockRoom, mockClient);

    matrixService = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
  });

  // ── Test app builder ──────────────────────────────────────────────

  Widget buildChatApp({String roomId = _roomId}) {
    final router = GoRouter(
      initialLocation: '/rooms/$roomId',
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
        ChangeNotifierProvider(create: (_) => PreferencesService()),
        ChangeNotifierProvider(create: (_) => MediaPlaybackService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  // ── Group 1: Basic Display ──────────────────────────────────────

  group('Chat screen — basic display', () {
    testWidgets('room loads with name and member count in app bar',
        (tester) async {
      stubTimeline(mockRoom, mockTimeline, []);

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      expect(find.text('Test Room'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
    });

    testWidgets('messages from timeline are displayed', (tester) async {
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
          senderId: '@bob:matrix.org',
        ),
        makeFakeEvent(
          room: mockRoom,
          eventId: r'$3',
          body: 'Third message',
        ),
      ];
      stubTimeline(mockRoom, mockTimeline, events);

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      expect(find.text('First message'), findsOneWidget);
      expect(find.text('Second message'), findsOneWidget);
      expect(find.text('Third message'), findsOneWidget);
    });

    testWidgets('room not found shows error', (tester) async {
      when(mockClient.getRoomById('!nonexistent:matrix.org')).thenReturn(null);

      await tester.pumpWidget(
        buildChatApp(roomId: '!nonexistent:matrix.org'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Room not found'), findsOneWidget);
    });

    testWidgets('empty room shows placeholder', (tester) async {
      stubTimeline(mockRoom, mockTimeline, []);

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      expect(find.text('No messages yet.\nSay hello!'), findsOneWidget);
    });

    testWidgets('loading state shows progress indicator', (tester) async {
      final completer = Completer<Timeline>();
      when(mockRoom.getTimeline(
        onUpdate: anyNamed('onUpdate'),
      ),).thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildChatApp());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // ── Group 2: Sending Messages ───────────────────────────────────

  group('Chat screen — sending messages', () {
    testWidgets('type and send text message', (tester) async {
      stubTimeline(mockRoom, mockTimeline, []);
      when(mockRoom.sendTextEvent(
        any,
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
      ),).thenAnswer((_) async => r'$sent');

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Type a message…'),
        'Hello world',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      verify(mockRoom.sendTextEvent('Hello world')).called(1);
    });

    testWidgets('empty compose bar shows mic instead of send',
        (tester) async {
      stubTimeline(mockRoom, mockTimeline, []);

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
    });
  });

  // ── Group 3: Typing Indicator ───────────────────────────────────

  group('Chat screen — typing indicator', () {
    testWidgets('typing indicator displays when others type', (tester) async {
      stubTimeline(mockRoom, mockTimeline, []);

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      when(mockRoom.typingUsers).thenReturn([
        User('@alice:matrix.org', room: mockRoom, displayName: 'Alice'),
      ]);
      syncController.add(
        SyncUpdate(nextBatch: 'batch_1', rooms: RoomsUpdate()),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('is typing'), findsOneWidget);
    });
  });

  // ── Group 4: App Bar Actions ────────────────────────────────────

  group('Chat screen — app bar actions', () {
    testWidgets('search button opens search mode', (tester) async {
      stubTimeline(mockRoom, mockTimeline, []);

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Search messages…'), findsOneWidget);
    });

    testWidgets('close search returns to chat view', (tester) async {
      stubTimeline(mockRoom, mockTimeline, []);

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Search messages…'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Test Room'), findsOneWidget);
      expect(find.text('Search messages…'), findsNothing);
    });

    testWidgets('pin badge shows when room has pinned events',
        (tester) async {
      stubRoomDefaults(
        mockRoom,
        mockClient,
        pinnedEventIds: [r'$evt1'],
      );
      stubTimeline(mockRoom, mockTimeline, []);

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
    });

    testWidgets('no pin badge when no pinned events', (tester) async {
      stubTimeline(mockRoom, mockTimeline, []);

      await tester.pumpWidget(buildChatApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.push_pin_rounded), findsNothing);
    });
  });
}

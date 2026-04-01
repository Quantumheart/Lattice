import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/rooms/widgets/room_tile.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
  MockSpec<Event>(),
  MockSpec<User>(),
  MockSpec<CallService>(),
])
import 'room_tile_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;
  late MockRoom mockRoom;
  late MockClient mockClient;
  late MockCallService mockCallService;
  late PreferencesService prefs;
  String? lastNavigatedRoom;

  MockEvent makeEvent({
    String type = EventTypes.Message,
    String messageType = MessageTypes.Text,
    String body = 'Hello',
    String senderId = '@alice:example.com',
    DateTime? originServerTs,
    bool redacted = false,
    Map<String, Object?>? content,
  }) {
    final event = MockEvent();
    when(event.type).thenReturn(type);
    when(event.messageType).thenReturn(messageType);
    when(event.body).thenReturn(body);
    when(event.senderId).thenReturn(senderId);
    when(event.originServerTs)
        .thenReturn(originServerTs ?? DateTime.now());
    when(event.redacted).thenReturn(redacted);
    when(event.content)
        .thenReturn(content ?? {'body': body, 'msgtype': messageType});
    when(event.room).thenReturn(mockRoom);
    when(event.redactedBecause).thenReturn(null);
    return event;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);

    mockMatrix = MockMatrixService();
    mockRoom = MockRoom();
    mockClient = MockClient();
    mockCallService = MockCallService();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.userID).thenReturn('@me:example.com');

    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.notificationCount).thenReturn(0);
    when(mockRoom.highlightCount).thenReturn(0);
    when(mockRoom.membership).thenReturn(Membership.join);
    when(mockRoom.lastEvent).thenReturn(null);
    when(mockRoom.avatar).thenReturn(null);
    when(mockRoom.directChatMatrixID).thenReturn(null);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.typingUsers).thenReturn([]);

    when(mockCallService.roomHasActiveCall(any)).thenReturn(false);
  });

  Widget buildTestWidget({
    bool isSelected = false,
    Set<String> memberships = const {},
  }) {
    lastNavigatedRoom = null;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: RoomTile(
              room: mockRoom,
              isSelected: isSelected,
              memberships: memberships,
              hasContextMenu: false,
            ),
          ),
          routes: [
            GoRoute(
              path: 'rooms/:roomId',
              name: Routes.room,
              builder: (context, state) {
                lastNavigatedRoom = state.pathParameters['roomId'];
                return Scaffold(
                  body: Text('Room ${state.pathParameters['roomId']}'),
                );
              },
            ),
          ],
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
        ChangeNotifierProvider<CallService>.value(value: mockCallService),
        ChangeNotifierProvider<PreferencesService>.value(value: prefs),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  // ── Unread badge ──────────────────────────────────────────

  group('Unread badge', () {
    testWidgets('no badge at 0 unread', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('0'), findsNothing);
    });

    testWidgets('shows count when unread > 0', (tester) async {
      when(mockRoom.notificationCount).thenReturn(5);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows 99+ when count exceeds 99', (tester) async {
      when(mockRoom.notificationCount).thenReturn(150);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('99+'), findsOneWidget);
    });
  });

  // ── Last message preview ──────────────────────────────────

  group('Last message preview', () {
    testWidgets('shows "No messages yet" when lastEvent is null',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('shows text body', (tester) async {
      final evt = makeEvent(body: 'Hello world');
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('shows image emoji for image message', (tester) async {
      final evt = makeEvent(messageType: MessageTypes.Image);
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Image'), findsOneWidget);
    });

    testWidgets('shows video emoji for video message', (tester) async {
      final evt = makeEvent(messageType: MessageTypes.Video);
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Video'), findsOneWidget);
    });

    testWidgets('shows file emoji for file message', (tester) async {
      final evt = makeEvent(messageType: MessageTypes.File);
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('File'), findsOneWidget);
    });

    testWidgets('shows audio emoji for audio message', (tester) async {
      final evt = makeEvent(messageType: MessageTypes.Audio);
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Audio'), findsOneWidget);
    });

    testWidgets('shows "Unable to decrypt" for BadEncrypted', (tester) async {
      final evt = makeEvent(messageType: MessageTypes.BadEncrypted);
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Unable to decrypt'), findsOneWidget);
    });

    testWidgets('shows "You deleted this message" for own redacted',
        (tester) async {
      final evt = makeEvent(redacted: true, senderId: '@me:example.com');
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('You deleted this message'), findsOneWidget);
    });

    testWidgets('shows "This message was deleted" for other redacted',
        (tester) async {
      final redactEvt = makeEvent();
      final evt = makeEvent(redacted: true);
      when(evt.redactedBecause).thenReturn(redactEvt);
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('This message was deleted'), findsOneWidget);
    });

    testWidgets('shows "Call in progress" for call invite', (tester) async {
      final evt = makeEvent(type: 'm.call.invite');
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Call in progress'), findsOneWidget);
    });

    testWidgets('shows "Call ended" for hangup', (tester) async {
      final evt = makeEvent(
        type: 'm.call.hangup',
        content: {'reason': 'user_hangup'},
      );
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Call ended'), findsOneWidget);
    });

    testWidgets('shows "Missed call" for hangup with invite_timeout',
        (tester) async {
      final evt = makeEvent(
        type: 'm.call.hangup',
        content: {'reason': 'invite_timeout'},
      );
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Missed call'), findsOneWidget);
    });
  });

  // ── Typing indicator ──────────────────────────────────────

  group('Typing indicator', () {
    testWidgets('shows typing text when enabled and users typing',
        (tester) async {
      SharedPreferences.setMockInitialValues({'typing_indicators': true});
      final sp = await SharedPreferences.getInstance();
      prefs = PreferencesService(prefs: sp);

      final typer = MockUser();
      when(typer.displayName).thenReturn('Bob');
      when(typer.id).thenReturn('@bob:example.com');
      when(mockRoom.typingUsers).thenReturn([typer]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Bob is typing'), findsOneWidget);
    });

    testWidgets('shows last message when typing disabled', (tester) async {
      SharedPreferences.setMockInitialValues({'typing_indicators': false});
      final sp = await SharedPreferences.getInstance();
      prefs = PreferencesService(prefs: sp);

      final typer = MockUser();
      when(typer.displayName).thenReturn('Bob');
      when(typer.id).thenReturn('@bob:example.com');
      when(mockRoom.typingUsers).thenReturn([typer]);
      final evt = makeEvent(body: 'Last msg');
      when(mockRoom.lastEvent).thenReturn(evt);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Bob is typing'), findsNothing);
      expect(find.text('Last msg'), findsOneWidget);
    });
  });

  // ── Call indicator ────────────────────────────────────────

  group('Call indicator', () {
    testWidgets('shows green call icon when room has active call',
        (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.call_rounded), findsOneWidget);
    });

    testWidgets('hides call icon when no active call', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.call_rounded), findsNothing);
    });
  });

  // ── Selection ─────────────────────────────────────────────

  group('Selection', () {
    testWidgets('applies primaryContainer background when selected',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(isSelected: true));
      await tester.pumpAndSettle();

      final material = tester.widgetList<Material>(find.byType(Material))
          .where((m) => m.color != null && m.color != Colors.transparent)
          .firstOrNull;
      expect(material, isNotNull);
    });
  });

  // ── Navigation ────────────────────────────────────────────

  group('Navigation', () {
    testWidgets('tap navigates to room route', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Room'));
      await tester.pumpAndSettle();

      expect(lastNavigatedRoom, '!room:example.com');
    });
  });

  // ── Timestamp ─────────────────────────────────────────────

  group('Timestamp', () {
    testWidgets('shows "now" for recent events', (tester) async {
      final evt = makeEvent(originServerTs: DateTime.now());
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('now'), findsOneWidget);
    });

    testWidgets('shows minutes for events within the hour', (tester) async {
      final evt = makeEvent(
        originServerTs: DateTime.now().subtract(const Duration(minutes: 15)),
      );
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('15m'), findsOneWidget);
    });

    testWidgets('shows hours for events within the day', (tester) async {
      final evt = makeEvent(
        originServerTs: DateTime.now().subtract(const Duration(hours: 3)),
      );
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('3h'), findsOneWidget);
    });

    testWidgets('shows days for events within the week', (tester) async {
      final evt = makeEvent(
        originServerTs: DateTime.now().subtract(const Duration(days: 2)),
      );
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('2d'), findsOneWidget);
    });

    testWidgets('shows DD/MM for events older than a week', (tester) async {
      final evt = makeEvent(originServerTs: DateTime(2025, 3, 15));
      when(mockRoom.lastEvent).thenReturn(evt);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('15/03'), findsOneWidget);
    });
  });

  // ── Active call controls ──────────────────────────────────

  group('Active call controls', () {
    testWidgets('shows Join button when room has active call and user is not connected',
        (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn(null);
      when(mockCallService.callState).thenReturn(LatticeCallState.idle);
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn({});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Leave'), findsNothing);
    });

    testWidgets('shows Leave button and elapsed time when user connected to this call',
        (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn('!room:example.com');
      when(mockCallService.callState).thenReturn(LatticeCallState.connected);
      when(mockCallService.callElapsed)
          .thenReturn(const Duration(seconds: 42));
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn({});

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('00:42'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('hides call controls when no active call', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Join'), findsNothing);
      expect(find.text('Leave'), findsNothing);
    });
  });

  // ── Call participant list ─────────────────────────────────

  group('Call participant list', () {
    late MockUser mockAlice;
    late MockUser mockBob;

    setUp(() {
      mockAlice = MockUser();
      when(mockAlice.displayName).thenReturn('Alice');
      when(mockAlice.id).thenReturn('@alice:example.com');

      mockBob = MockUser();
      when(mockBob.displayName).thenReturn('Bob');
      when(mockBob.id).thenReturn('@bob:example.com');
    });

    testWidgets('shows participant names when call is active', (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn(null);
      when(mockCallService.callState).thenReturn(LatticeCallState.idle);
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn({'@alice:example.com', '@bob:example.com'});
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockRoom.unsafeGetUserFromMemoryOrFallback('@alice:example.com'))
          .thenReturn(mockAlice);
      when(mockRoom.unsafeGetUserFromMemoryOrFallback('@bob:example.com'))
          .thenReturn(mockBob);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows You first when user is connected', (tester) async {
      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn('!room:example.com');
      when(mockCallService.callState).thenReturn(LatticeCallState.connected);
      when(mockCallService.callElapsed)
          .thenReturn(const Duration(seconds: 10));
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn({'@alice:example.com', '@me:example.com'});
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockRoom.unsafeGetUserFromMemoryOrFallback('@alice:example.com'))
          .thenReturn(mockAlice);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('You'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows + N more when more than 5 participants', (tester) async {
      final userIds = <String>{};
      for (var i = 0; i < 7; i++) {
        final id = '@user$i:example.com';
        userIds.add(id);
        final user = MockUser();
        when(user.displayName).thenReturn('User $i');
        when(user.id).thenReturn(id);
        when(mockRoom.unsafeGetUserFromMemoryOrFallback(id)).thenReturn(user);
      }

      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn(null);
      when(mockCallService.callState).thenReturn(LatticeCallState.idle);
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn(userIds);
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('+ 2 more'), findsOneWidget);
    });

    testWidgets('expands on tap and shows Show less', (tester) async {
      final userIds = <String>{};
      for (var i = 0; i < 7; i++) {
        final id = '@user$i:example.com';
        userIds.add(id);
        final user = MockUser();
        when(user.displayName).thenReturn('User $i');
        when(user.id).thenReturn(id);
        when(mockRoom.unsafeGetUserFromMemoryOrFallback(id)).thenReturn(user);
      }

      when(mockCallService.roomHasActiveCall('!room:example.com'))
          .thenReturn(true);
      when(mockCallService.activeCallRoomId).thenReturn(null);
      when(mockCallService.callState).thenReturn(LatticeCallState.idle);
      when(mockCallService.callParticipantUserIds('!room:example.com'))
          .thenReturn(userIds);
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ 2 more'));
      await tester.pumpAndSettle();

      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('User 6'), findsOneWidget);
      expect(find.text('+ 2 more'), findsNothing);
    });
  });
}

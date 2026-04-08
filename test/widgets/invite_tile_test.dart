import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/features/rooms/widgets/room_list.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
])
import 'invite_tile_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;
  late MockRoom mockInvitedRoom;
  late MockClient mockClient;
  late PreferencesService prefs;
  late SelectionService selectionService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);

    mockMatrix = MockMatrixService();
    mockInvitedRoom = MockRoom();
    mockClient = MockClient();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());

    when(mockInvitedRoom.id).thenReturn('!invited:example.com');
    when(mockInvitedRoom.getLocalizedDisplayname()).thenReturn('Test Invite');
    when(mockInvitedRoom.isSpace).thenReturn(false);
    when(mockInvitedRoom.isDirectChat).thenReturn(false);
    when(mockInvitedRoom.membership).thenReturn(Membership.invite);
    when(mockInvitedRoom.client).thenReturn(mockClient);
    when(mockInvitedRoom.avatar).thenReturn(null);
    when(mockInvitedRoom.directChatMatrixID).thenReturn(null);
    when(mockInvitedRoom.getState(EventTypes.RoomMember, '@me:example.com'))
        .thenReturn(Event(
      type: EventTypes.RoomMember,
      content: {'membership': 'invite'},
      senderId: '@alice:example.com',
      eventId: r'$inv',
      room: mockInvitedRoom,
      originServerTs: DateTime.now(),
    ),);
    when(mockInvitedRoom.unsafeGetUserFromMemoryOrFallback('@alice:example.com'))
        .thenReturn(User('@alice:example.com',
            room: mockInvitedRoom, displayName: 'Alice',),);

    when(mockClient.rooms).thenReturn([mockInvitedRoom]);

    selectionService = SelectionService(client: mockClient);
    when(mockMatrix.selection).thenReturn(selectionService);
  });

  late GoRouter testRouter;
  String? lastNavigatedRoom;

  Widget buildTestWidget() {
    lastNavigatedRoom = null;
    testRouter = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: RoomList()),
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
        ChangeNotifierProvider<SelectionService>.value(value: selectionService),
        ChangeNotifierProvider(create: (ctx) => CallService(client: ctx.read<MatrixService>().client)),
        ChangeNotifierProvider<PreferencesService>.value(value: prefs),
      ],
      child: MaterialApp.router(
        routerConfig: testRouter,
      ),
    );
  }

  group('InviteTile in RoomList', () {
    testWidgets('displays invite room with inviter name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Test Invite'), findsOneWidget);
      expect(find.text('Invited by Alice'), findsOneWidget);
    });

    testWidgets('shows "Pending invite" when inviter is unknown',
        (tester) async {
      when(mockInvitedRoom.getState(EventTypes.RoomMember, '@me:example.com'))
          .thenReturn(null);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Pending invite'), findsOneWidget);
    });

    testWidgets('accept calls join and selects room', (tester) async {
      when(mockInvitedRoom.join()).thenAnswer((_) async => '');
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap the invite tile (the InkWell) to accept.
      await tester.tap(find.text('Test Invite'));
      await tester.pumpAndSettle();

      verify(mockInvitedRoom.join()).called(1);
      expect(lastNavigatedRoom, '!invited:example.com');
    });

    testWidgets('accept shows snackbar on failure', (tester) async {
      when(mockInvitedRoom.join()).thenThrow(Exception('Server error'));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Invite'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Server error'), findsOneWidget);
    });

    testWidgets('shows loading indicator during accept', (tester) async {
      final completer = Completer<String>();
      when(mockInvitedRoom.join()).thenAnswer((_) => completer.future);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Invite'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Cleanup.
      completer.complete('');
      await tester.pumpAndSettle();
    });

    testWidgets('decline shows confirmation and calls leave', (tester) async {
      when(mockInvitedRoom.leave()).thenAnswer((_) async {});
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap the decline button (X icon).
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear.
      expect(find.text('Decline invite'), findsOneWidget);
      expect(find.text('Decline invite to Test Invite?'), findsOneWidget);

      // Confirm decline.
      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await tester.pumpAndSettle();

      verify(mockInvitedRoom.leave()).called(1);
    });

    testWidgets('decline cancellation does not call leave', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Cancel the confirmation.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(mockInvitedRoom.leave());
    });

    testWidgets('decline shows snackbar on failure', (tester) async {
      when(mockInvitedRoom.leave()).thenThrow(Exception('Network error'));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Network error'), findsOneWidget);
    });

    testWidgets('concurrent tap guard prevents double accept', (tester) async {
      final completer = Completer<String>();
      when(mockInvitedRoom.join()).thenAnswer((_) => completer.future);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // First tap starts the join.
      await tester.tap(find.text('Test Invite'));
      await tester.pump();

      // Decline button should be disabled during join.
      final iconButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Decline invite'),
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButton.onPressed, isNull);

      completer.complete('');
      await tester.pumpAndSettle();
    });
  });
}

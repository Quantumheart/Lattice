import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/features/notifications/services/inbox_controller.dart';
import 'package:lattice/features/spaces/widgets/space_rail.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service_test.mocks.dart' show MockFlutterSecureStorage;
import 'space_management_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])

// ── Constants ─────────────────────────────────────────────────────────

const _myUserId = '@me:matrix.org';
const _spaceId1 = '!space1:matrix.org';
const _spaceId2 = '!space2:matrix.org';
const _roomId1 = '!room1:matrix.org';

// ── Helpers ───────────────────────────────────────────────────────────

SpaceChild _makeSpaceChild(String roomId) {
  return SpaceChild.fromState(
    StrippedStateEvent(
      type: EventTypes.SpaceChild,
      content: {},
      senderId: '',
      stateKey: roomId,
    ),
  );
}

MockRoom makeSpace({
  required MockClient client,
  required String id,
  required String displayName,
  List<SpaceChild> spaceChildren = const [],
  Membership membership = Membership.join,
  int notificationCount = 0,
}) {
  final space = MockRoom();
  when(space.id).thenReturn(id);
  when(space.getLocalizedDisplayname()).thenReturn(displayName);
  when(space.client).thenReturn(client);
  when(space.isSpace).thenReturn(true);
  when(space.membership).thenReturn(membership);
  when(space.spaceChildren).thenReturn(spaceChildren);
  when(space.notificationCount).thenReturn(notificationCount);
  when(space.avatar).thenReturn(null);
  when(space.lastEvent).thenReturn(null);
  when(space.canChangeStateEvent(any)).thenReturn(false);
  when(client.getRoomById(id)).thenReturn(space);
  return space;
}

MockRoom makeRoom({
  required MockClient client,
  required String id,
  required String displayName,
  int notificationCount = 0,
}) {
  final room = MockRoom();
  when(room.id).thenReturn(id);
  when(room.getLocalizedDisplayname()).thenReturn(displayName);
  when(room.client).thenReturn(client);
  when(room.isSpace).thenReturn(false);
  when(room.membership).thenReturn(Membership.join);
  when(room.notificationCount).thenReturn(notificationCount);
  when(room.lastEvent).thenReturn(null);
  when(client.getRoomById(id)).thenReturn(room);
  return room;
}

// ── Tests ─────────────────────────────────────────────────────────────

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;
  late CachedStreamController<SyncUpdate> syncController;
  late InboxController inboxController;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    syncController = CachedStreamController<SyncUpdate>();

    when(mockClient.userID).thenReturn(_myUserId);
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(syncController);
    when(mockClient.encryption).thenReturn(null);
    when(mockClient.homeserver).thenReturn(Uri.parse('https://matrix.org'));
    when(mockClient.fetchOwnProfile()).thenAnswer(
      (_) async => Profile(userId: _myUserId, displayName: 'Me'),
    );

    matrixService = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );

    clientManager = ClientManager(storage: mockStorage);

    inboxController = InboxController(client: mockClient);
  });

  // ── Test app builder ──────────────────────────────────────────────

  Widget buildSpaceTestApp() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          name: Routes.home,
          builder: (context, state) => const Scaffold(body: SpaceRail()),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<SelectionService>.value(
            value: matrixService.selection,),
        ChangeNotifierProvider(create: (ctx) => CallService(client: ctx.read<MatrixService>().client)),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
        ChangeNotifierProvider(create: (_) => PreferencesService()),
        ChangeNotifierProvider<InboxController>.value(value: inboxController),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  // ── Group 1: Space Display ──────────────────────────────────────

  group('Space rail — display', () {
    testWidgets('shows joined spaces with first-letter labels',
        (tester) async {
      final space1 = makeSpace(
        client: mockClient,
        id: _spaceId1,
        displayName: 'Alpha',
      );
      final space2 = makeSpace(
        client: mockClient,
        id: _spaceId2,
        displayName: 'Beta',
      );
      when(mockClient.rooms).thenReturn([space1, space2]);

      await tester.pumpWidget(buildSpaceTestApp());
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('Home icon is selected by default', (tester) async {
      await tester.pumpWidget(buildSpaceTestApp());
      await tester.pumpAndSettle();

      expect(find.text('H'), findsOneWidget);
      expect(matrixService.selection.selectedSpaceIds, isEmpty);
    });
  });

  // ── Group 2: Space Selection ──────────────────────────────────

  group('Space rail — selection', () {
    testWidgets('tap space selects it', (tester) async {
      final space = makeSpace(
        client: mockClient,
        id: _spaceId1,
        displayName: 'Alpha',
      );
      when(mockClient.rooms).thenReturn([space]);

      await tester.pumpWidget(buildSpaceTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      expect(matrixService.selection.selectedSpaceIds, contains(_spaceId1));
    });

    testWidgets('tap selected space deselects it', (tester) async {
      final space = makeSpace(
        client: mockClient,
        id: _spaceId1,
        displayName: 'Alpha',
      );
      when(mockClient.rooms).thenReturn([space]);

      await tester.pumpWidget(buildSpaceTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(matrixService.selection.selectedSpaceIds, contains(_spaceId1));

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(matrixService.selection.selectedSpaceIds, isEmpty);
    });

    testWidgets('tapping Home clears space selection', (tester) async {
      final space = makeSpace(
        client: mockClient,
        id: _spaceId1,
        displayName: 'Alpha',
      );
      when(mockClient.rooms).thenReturn([space]);
      matrixService.selection.selectSpace(_spaceId1);

      await tester.pumpWidget(buildSpaceTestApp());
      await tester.pumpAndSettle();

      expect(matrixService.selection.selectedSpaceIds, isNotEmpty);

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(matrixService.selection.selectedSpaceIds, isEmpty);
    });
  });

  // ── Group 3: Unread Badge ──────────────────────────────────────

  group('Space rail — unread badge', () {
    testWidgets('unread badge appears when child rooms have notifications',
        (tester) async {
      final childRoom = makeRoom(
        client: mockClient,
        id: _roomId1,
        displayName: 'General',
        notificationCount: 5,
      );
      final space = makeSpace(
        client: mockClient,
        id: _spaceId1,
        displayName: 'Alpha',
        spaceChildren: [_makeSpaceChild(_roomId1)],
      );
      when(mockClient.rooms).thenReturn([space, childRoom]);

      await tester.pumpWidget(buildSpaceTestApp());
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('no badge when child rooms have zero notifications',
        (tester) async {
      final childRoom = makeRoom(
        client: mockClient,
        id: _roomId1,
        displayName: 'General',
      );
      final space = makeSpace(
        client: mockClient,
        id: _spaceId1,
        displayName: 'Alpha',
        spaceChildren: [_makeSpaceChild(_roomId1)],
      );
      when(mockClient.rooms).thenReturn([space, childRoom]);

      await tester.pumpWidget(buildSpaceTestApp());
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      final badgeTexts = find.textContaining(RegExp(r'^\d+$'));
      expect(badgeTexts, findsNothing);
    });
  });

  // ── Group 4: Invited Spaces ────────────────────────────────────

  group('Space rail — invited spaces', () {
    testWidgets('invited spaces appear with reduced opacity',
        (tester) async {
      final invitedSpace = makeSpace(
        client: mockClient,
        id: _spaceId1,
        displayName: 'Invited Space',
        membership: Membership.invite,
      );
      when(mockClient.rooms).thenReturn([invitedSpace]);

      await tester.pumpWidget(buildSpaceTestApp());
      await tester.pumpAndSettle();

      final opacityFinder = find.ancestor(
        of: find.text('I'),
        matching: find.byType(Opacity),
      );
      expect(opacityFinder, findsOneWidget);

      final opacity = tester.widget<Opacity>(opacityFinder);
      expect(opacity.opacity, 0.7);
    });
  });
}

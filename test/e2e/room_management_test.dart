import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/widgets/new_room_dialog.dart';
import 'package:kohera/features/rooms/widgets/room_details_panel.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service_test.mocks.dart' show MockFlutterSecureStorage;
import 'room_management_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<User>(),
])

// ── Constants ─────────────────────────────────────────────────────────

const _roomId = '!room:example.com';
const _spaceId = '!space:example.com';
const _newRoomId = '!newroom:example.com';
const _myUserId = '@me:example.com';

// ── Helpers ───────────────────────────────────────────────────────────

void stubClientDefaults(
  MockClient mockClient,
  CachedStreamController<SyncUpdate> syncController,
) {
  when(mockClient.userID).thenReturn(_myUserId);
  when(mockClient.rooms).thenReturn([]);
  when(mockClient.onSync).thenReturn(syncController);
  when(mockClient.encryption).thenReturn(null);
  when(mockClient.homeserver).thenReturn(Uri.parse('https://example.com'));
  when(mockClient.updateUserDeviceKeys()).thenAnswer((_) async {});
  when(mockClient.userDeviceKeys).thenReturn({});
}

void stubRoomDefaults(MockRoom mockRoom, MockClient mockClient) {
  when(mockRoom.id).thenReturn(_roomId);
  when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
  when(mockRoom.client).thenReturn(mockClient);
  when(mockRoom.topic).thenReturn('');
  when(mockRoom.avatar).thenReturn(null);
  when(mockRoom.encrypted).thenReturn(false);
  when(mockRoom.isDirectChat).thenReturn(false);
  when(mockRoom.isFavourite).thenReturn(false);
  when(mockRoom.pushRuleState).thenReturn(PushRuleState.notify);
  when(mockRoom.canChangeStateEvent(any)).thenReturn(false);
  when(mockRoom.canChangePowerLevel).thenReturn(false);
  when(mockRoom.canKick).thenReturn(false);
  when(mockRoom.canBan).thenReturn(false);
  when(mockRoom.summary).thenReturn(
    RoomSummary.fromJson({'m.joined_member_count': 3}),
  );
  when(mockRoom.requestParticipants(any)).thenAnswer((_) async => []);
  when(mockRoom.getPowerLevelByUserId(any)).thenReturn(0);
}

void stubCreateRoom(MockClient mockClient) {
  when(mockClient.createRoom(
    name: anyNamed('name'),
    topic: anyNamed('topic'),
    visibility: anyNamed('visibility'),
    initialState: anyNamed('initialState'),
    invite: anyNamed('invite'),
  ),).thenAnswer((_) async => _newRoomId);
  when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
      .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
}

MockUser makeUser(String id, String displayName, {Room? room}) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  when(user.room).thenReturn(room ?? MockRoom());
  return user;
}

// ── Tests ─────────────────────────────────────────────────────────────

void main() {
  late MockClient mockClient;
  late MockRoom mockRoom;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late CachedStreamController<SyncUpdate> syncController;

  setUp(() {
    mockClient = MockClient();
    mockRoom = MockRoom();
    mockStorage = MockFlutterSecureStorage();
    syncController = CachedStreamController<SyncUpdate>();

    stubClientDefaults(mockClient, syncController);
    stubRoomDefaults(mockRoom, mockClient);
    when(mockClient.getRoomById(_roomId)).thenReturn(mockRoom);

    matrixService = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
  });

  // ── New Room Dialog builder ─────────────────────────────────────

  Widget buildNewRoomApp() {
    return MaterialApp(
      home: ChangeNotifierProvider<MatrixService>.value(
        value: matrixService,
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  unawaited(NewRoomDialog.show(
                    context,
                    matrixService: matrixService,
                  ),);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openNewRoomDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildNewRoomApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  // ── Room Details builder ────────────────────────────────────────

  Widget buildDetailsApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<SelectionService>.value(
            value: matrixService.selection,),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: RoomDetailsPanel(roomId: _roomId),
        ),
      ),
    );
  }

  // ── Group 1: Room Creation ──────────────────────────────────────

  group('Room creation', () {
    testWidgets('create private room with name and topic', (tester) async {
      stubCreateRoom(mockClient);
      await openNewRoomDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'My Room',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Topic (optional)'),
        'A topic',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(mockClient.createRoom(
        name: 'My Room',
        topic: 'A topic',
        visibility: Visibility.private,
        initialState: anyNamed('initialState'),
      ),).called(1);
      verify(mockClient.waitForRoomInSync(_newRoomId, join: true)).called(1);
      expect(matrixService.selection.selectedRoomId, _newRoomId);
    });

    testWidgets('create public room disables encryption', (tester) async {
      stubCreateRoom(mockClient);
      await openNewRoomDialog(tester);

      await tester.tap(find.text('Public room'));
      await tester.pumpAndSettle();

      final encryptionSwitch = tester.widget<Switch>(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'Enable encryption'),
          matching: find.byType(Switch),
        ),
      );
      expect(encryptionSwitch.onChanged, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Public Room',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      final captured = verify(mockClient.createRoom(
        name: 'Public Room',
        visibility: Visibility.public,
        initialState: captureAnyNamed('initialState'),
      ),).captured;
      final initialState = captured.last as List<StateEvent>;
      expect(
        initialState.any((s) => s.type == EventTypes.Encryption),
        isFalse,
      );
    });

    testWidgets('create room with invited users', (tester) async {
      stubCreateRoom(mockClient);
      await openNewRoomDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Invite Room',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite users (optional)'),
        '@alice:example.com',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, '@alice:example.com'), findsOneWidget);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(mockClient.createRoom(
        name: 'Invite Room',
        visibility: Visibility.private,
        initialState: anyNamed('initialState'),
        invite: ['@alice:example.com'],
      ),).called(1);
    });

    testWidgets('creation failure shows error and keeps dialog open',
        (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        visibility: anyNamed('visibility'),
        initialState: anyNamed('initialState'),
        invite: anyNamed('invite'),
      ),).thenThrow(Exception('Server error'));

      await openNewRoomDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Fail Room',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('New Room'), findsOneWidget);
      expect(find.textContaining('Server error'), findsOneWidget);
    });

    testWidgets('empty name shows validation error', (tester) async {
      await openNewRoomDialog(tester);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
      verifyNever(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        visibility: anyNamed('visibility'),
        initialState: anyNamed('initialState'),
        invite: anyNamed('invite'),
      ),);
    });

    testWidgets('cancel closes dialog without creating room', (tester) async {
      await openNewRoomDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New Room'), findsNothing);
      verifyNever(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        visibility: anyNamed('visibility'),
        initialState: anyNamed('initialState'),
        invite: anyNamed('invite'),
      ),);
    });

    testWidgets('invalid MXID in invite field shows error', (tester) async {
      await openNewRoomDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Invite users (optional)'),
        'invalid-id',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });
  });

  // ── Group 2: Space Parenting ────────────────────────────────────

  group('Room creation — space parenting', () {
    testWidgets('room created inside selected space is auto-parented',
        (tester) async {
      final mockSpace = MockRoom();
      when(mockSpace.id).thenReturn(_spaceId);
      when(mockSpace.getLocalizedDisplayname()).thenReturn('My Space');
      when(mockSpace.canChangeStateEvent('m.space.child')).thenReturn(true);
      when(mockSpace.setSpaceChild(any)).thenAnswer((_) async {});
      when(mockClient.getRoomById(_spaceId)).thenReturn(mockSpace);

      matrixService.selection.selectSpace(_spaceId);
      stubCreateRoom(mockClient);

      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<MatrixService>.value(
          value: matrixService,
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    unawaited(NewRoomDialog.show(
                      context,
                      matrixService: matrixService,
                    ),);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Add to My Space'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Space Room',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(mockSpace.setSpaceChild(_newRoomId)).called(1);
    });
  });

  // ── Group 3: Invite from Room Details ───────────────────────────

  group('Room details — invite', () {
    testWidgets('invite user via room details panel', (tester) async {
      when(mockRoom.invite(any)).thenAnswer((_) async {});
      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(find.text('Invite user'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Matrix ID'),
        '@bob:example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Invite'));
      await tester.pumpAndSettle();

      verify(mockRoom.invite('@bob:example.com')).called(1);
    });

    testWidgets('invalid MXID shows error in invite dialog', (tester) async {
      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Matrix ID'),
        'invalid-id',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('empty MXID shows error in invite dialog', (tester) async {
      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Invite'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a Matrix ID'), findsOneWidget);
    });
  });

  // ── Group 4: Leave Room ─────────────────────────────────────────

  group('Room details — leave', () {
    testWidgets('leave room with confirmation', (tester) async {
      when(mockRoom.leave()).thenAnswer((_) async {});
      matrixService.selection.selectRoom(_roomId);

      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.text('Leave room?'), findsOneWidget);
      expect(find.text('You will leave "Test Room".'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      verify(mockRoom.leave()).called(1);
      expect(matrixService.selection.selectedRoomId, isNull);
    });

    testWidgets('cancel leave does not call room.leave', (tester) async {
      matrixService.selection.selectRoom(_roomId);

      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      verifyNever(mockRoom.leave());
      expect(matrixService.selection.selectedRoomId, _roomId);
    });
  });

  // ── Group 5: Kick & Ban ─────────────────────────────────────────

  group('Room details — kick and ban', () {
    late MockUser alice;

    setUp(() {
      alice = makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);
    });

    testWidgets('kick member from bottom sheet', (tester) async {
      when(mockRoom.canKick).thenReturn(true);
      when(mockRoom.kick(any)).thenAnswer((_) async {});

      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kick'));
      await tester.pumpAndSettle();

      expect(find.text('Kick member?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Kick'));
      await tester.pumpAndSettle();

      verify(mockRoom.kick('@alice:example.com')).called(1);
    });

    testWidgets('ban member from bottom sheet', (tester) async {
      when(mockRoom.canBan).thenReturn(true);
      when(mockRoom.ban(any)).thenAnswer((_) async {});

      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ban'));
      await tester.pumpAndSettle();

      expect(find.text('Ban member?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Ban'));
      await tester.pumpAndSettle();

      verify(mockRoom.ban('@alice:example.com')).called(1);
    });

    testWidgets('cancel kick does not call room.kick', (tester) async {
      when(mockRoom.canKick).thenReturn(true);

      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kick'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      verifyNever(mockRoom.kick(any));
    });

    testWidgets('member sheet hides kick/ban for self', (tester) async {
      final me = makeUser(_myUserId, 'Me', room: mockRoom);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [me]);
      when(mockRoom.canKick).thenReturn(true);
      when(mockRoom.canBan).thenReturn(true);

      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Me'));
      await tester.pumpAndSettle();

      expect(find.text('Kick'), findsNothing);
      expect(find.text('Ban'), findsNothing);
    });

    testWidgets('member sheet hides kick/ban without permissions',
        (tester) async {
      when(mockRoom.canKick).thenReturn(false);
      when(mockRoom.canBan).thenReturn(false);

      await tester.pumpWidget(buildDetailsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.text('Kick'), findsNothing);
      expect(find.text('Ban'), findsNothing);
    });
  });
}

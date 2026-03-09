import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/rooms/widgets/room_details_panel.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/mockito.dart';

import '../test/helpers/matrix_sdk_internals.dart';
import '../test/helpers/test_utils.dart';
import 'helpers/mocks.dart';
import 'helpers/test_app.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _roomId = '!room:example.com';
const _newRoomId = '!newroom:example.com';

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

    when(mockClient.rooms).thenReturn([]);
    stubLoggedInClient(mockClient, syncController);
    stubRoomDefaults(mockRoom, mockClient);
    when(mockClient.getRoomById(_roomId)).thenReturn(mockRoom);

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

  // ── Integration Tests ────────────────────────────────────────────────────

  group('Room management integration', () {
    testWidgets('create room navigates to room screen', (tester) async {
      stubCreateRoom(mockClient);
      final newRoom = MockRoom();
      stubRoomDefaults(newRoom, mockClient);
      when(newRoom.id).thenReturn(_newRoomId);
      when(newRoom.getLocalizedDisplayname()).thenReturn('My New Room');
      when(mockClient.getRoomById(_newRoomId)).thenReturn(newRoom);

      await tester.pumpWidget(buildRoomTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
      ),);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('New Room'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'My New Room',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('My New Room'), findsWidgets);
      expect(matrixService.selectedRoomId, _newRoomId);
    });

    testWidgets('navigate to room details and back', (tester) async {
      matrixService.selectRoom(_roomId);

      await tester.pumpWidget(buildRoomTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
      ),);
      await tester.pumpAndSettle();

      expect(find.text('Test Room'), findsWidgets);

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.byType(RoomDetailsPanel), findsOneWidget);
      expect(find.text('Test Room'), findsWidgets);
      expect(find.text('3 members'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(RoomDetailsPanel), findsNothing);
      expect(find.text('Test Room'), findsWidgets);
    });

    testWidgets('leave room from details navigates to home', (tester) async {
      when(mockRoom.leave()).thenAnswer((_) async {});
      matrixService.selectRoom(_roomId);

      await tester.pumpWidget(buildRoomTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
      ),);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.byType(RoomDetailsPanel), findsOneWidget);

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.text('Leave room?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      verify(mockRoom.leave()).called(1);
      expect(matrixService.selectedRoomId, isNull);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('full flow — create room, view details, invite user, leave',
        (tester) async {
      stubCreateRoom(mockClient);
      final newRoom = MockRoom();
      stubRoomDefaults(newRoom, mockClient);
      when(newRoom.id).thenReturn(_newRoomId);
      when(newRoom.getLocalizedDisplayname()).thenReturn('Flow Room');
      when(newRoom.invite(any)).thenAnswer((_) async {});
      when(newRoom.leave()).thenAnswer((_) async {});
      when(mockClient.getRoomById(_newRoomId)).thenReturn(newRoom);

      await tester.pumpWidget(buildRoomTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
      ),);
      await tester.pumpAndSettle();

      // Create room
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Flow Room',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Flow Room'), findsWidgets);
      expect(matrixService.selectedRoomId, _newRoomId);

      // Navigate to details
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.byType(RoomDetailsPanel), findsOneWidget);

      // Invite user
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(find.text('Invite user'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Matrix ID'),
        '@bob:example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Invite'));
      await tester.pumpAndSettle();

      verify(newRoom.invite('@bob:example.com')).called(1);

      // Leave room
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.text('Leave room?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      verify(newRoom.leave()).called(1);
      expect(matrixService.selectedRoomId, isNull);
      expect(find.text('Home'), findsOneWidget);
    });
  });
}

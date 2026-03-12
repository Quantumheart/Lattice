import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/rooms/widgets/add_existing_rooms_dialog.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:matrix/src/utils/space_child.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
])
import 'add_existing_rooms_dialog_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;
  late MockRoom mockSpace;
  late MockClient mockClient;

  MockRoom makeRoom(String id, String name) {
    final room = MockRoom();
    when(room.id).thenReturn(id);
    when(room.getLocalizedDisplayname()).thenReturn(name);
    when(room.membership).thenReturn(Membership.join);
    when(room.isSpace).thenReturn(false);
    when(room.avatar).thenReturn(null);
    when(room.directChatMatrixID).thenReturn(null);
    when(room.client).thenReturn(mockClient);
    return room;
  }

  setUp(() {
    mockMatrix = MockMatrixService();
    mockSpace = MockRoom();
    mockClient = MockClient();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockSpace.spaceChildren).thenReturn([]);
    when(mockSpace.setSpaceChild(any)).thenAnswer((_) async {});
  });

  Widget buildTestWidget({List<Room>? clientRooms}) {
    when(mockClient.rooms).thenReturn(clientRooms ?? []);

    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => AddExistingRoomsDialog.show(
                context,
                space: mockSpace,
                matrixService: mockMatrix,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester, {List<Room>? clientRooms}) async {
    await tester.pumpWidget(buildTestWidget(clientRooms: clientRooms));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('AddExistingRoomsDialog', () {
    testWidgets('shows empty state when all rooms in space', (tester) async {
      await openDialog(tester, clientRooms: []);

      expect(
        find.text('All your rooms are already in this space.'),
        findsOneWidget,
      );
    });

    testWidgets('shows eligible rooms', (tester) async {
      final room1 = makeRoom('!r1:x', 'Alpha');
      final room2 = makeRoom('!r2:x', 'Beta');

      await openDialog(tester, clientRooms: [room1, room2]);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('excludes rooms already in space', (tester) async {
      final room1 = makeRoom('!r1:x', 'Alpha');
      final room2 = makeRoom('!r2:x', 'Beta');

      when(mockSpace.spaceChildren).thenReturn([
        SpaceChild.fromState(
          StrippedStateEvent(
            type: EventTypes.SpaceChild,
            content: {},
            senderId: '',
            stateKey: '!r1:x',
          ),
        ),
      ]);

      await openDialog(tester, clientRooms: [room1, room2]);

      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('excludes space rooms', (tester) async {
      final room1 = makeRoom('!r1:x', 'Alpha');
      when(room1.isSpace).thenReturn(true);

      await openDialog(tester, clientRooms: [room1]);

      expect(
        find.text('All your rooms are already in this space.'),
        findsOneWidget,
      );
    });

    testWidgets('search filters by display name', (tester) async {
      final room1 = makeRoom('!r1:x', 'Alpha');
      final room2 = makeRoom('!r2:x', 'Beta');

      await openDialog(tester, clientRooms: [room1, room2]);

      await tester.enterText(find.byType(TextField), 'alp');
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
    });

    testWidgets('selection updates Add button text', (tester) async {
      final room1 = makeRoom('!r1:x', 'Alpha');
      final room2 = makeRoom('!r2:x', 'Beta');

      await openDialog(tester, clientRooms: [room1, room2]);

      expect(find.text('Add (0)'), findsOneWidget);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(find.text('Add (1)'), findsOneWidget);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(find.text('Add (2)'), findsOneWidget);
    });

    testWidgets('submit calls setSpaceChild for each selected room',
        (tester) async {
      final room1 = makeRoom('!r1:x', 'Alpha');
      final room2 = makeRoom('!r2:x', 'Beta');

      await openDialog(tester, clientRooms: [room1, room2]);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add (2)'));
      await tester.pumpAndSettle();

      verify(mockSpace.setSpaceChild('!r1:x')).called(1);
      verify(mockSpace.setSpaceChild('!r2:x')).called(1);
      verify(mockMatrix.invalidateSpaceTree()).called(1);
    });

    testWidgets('partial failure shows SnackBar', (tester) async {
      final room1 = makeRoom('!r1:x', 'Alpha');
      final room2 = makeRoom('!r2:x', 'Beta');

      when(mockSpace.setSpaceChild('!r2:x')).thenThrow(Exception('fail'));

      await openDialog(tester, clientRooms: [room1, room2]);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to add 1 room(s)'), findsOneWidget);
    });
  });
}

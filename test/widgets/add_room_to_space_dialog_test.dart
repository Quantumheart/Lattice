import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/rooms/widgets/add_room_to_space_dialog.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
])
import 'add_room_to_space_dialog_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;
  late MockRoom mockRoom;
  late MockClient mockClient;

  MockRoom makeSpace(String id, String name, {bool canEdit = true}) {
    final space = MockRoom();
    when(space.id).thenReturn(id);
    when(space.getLocalizedDisplayname()).thenReturn(name);
    when(space.canChangeStateEvent('m.space.child')).thenReturn(canEdit);
    when(space.avatar).thenReturn(null);
    when(space.directChatMatrixID).thenReturn(null);
    when(space.client).thenReturn(mockClient);
    when(space.setSpaceChild(any, suggested: anyNamed('suggested')))
        .thenAnswer((_) async {});
    return space;
  }

  setUp(() {
    mockMatrix = MockMatrixService();
    mockRoom = MockRoom();
    mockClient = MockClient();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockRoom.id).thenReturn('!room:example.com');
  });

  Widget buildTestWidget({
    List<Room>? spaces,
    Set<String> memberships = const {},
  }) {
    when(mockMatrix.spaces).thenReturn(spaces ?? []);
    when(mockMatrix.spaceMemberships('!room:example.com'))
        .thenReturn(memberships);

    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => AddRoomToSpaceDialog.show(
                context,
                room: mockRoom,
                matrixService: mockMatrix,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    List<Room>? spaces,
    Set<String> memberships = const {},
    bool hasListView = false,
  }) async {
    await tester.pumpWidget(
      buildTestWidget(spaces: spaces, memberships: memberships),
    );
    await tester.tap(find.text('Open'));
    if (hasListView) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      await tester.pumpAndSettle();
    }
  }

  group('AddRoomToSpaceDialog', () {
    testWidgets('shows empty state when room in all spaces', (tester) async {
      await openDialog(tester, spaces: []);

      expect(
        find.text('This room is already in all your spaces.'),
        findsOneWidget,
      );
    });

    testWidgets('shows eligible spaces', (tester) async {
      final space1 = makeSpace('!s1:x', 'Space A');
      final space2 = makeSpace('!s2:x', 'Space B');

      await openDialog(tester, spaces: [space1, space2], hasListView: true);

      expect(find.text('Space A'), findsOneWidget);
      expect(find.text('Space B'), findsOneWidget);
    });

    testWidgets('excludes spaces where room is already a member',
        (tester) async {
      final space1 = makeSpace('!s1:x', 'Space A');
      final space2 = makeSpace('!s2:x', 'Space B');

      await openDialog(
        tester,
        spaces: [space1, space2],
        memberships: {'!s1:x'},
        hasListView: true,
      );

      expect(find.text('Space A'), findsNothing);
      expect(find.text('Space B'), findsOneWidget);
    });

    testWidgets('excludes spaces user cannot edit', (tester) async {
      makeSpace('!s1:x', 'Space A', canEdit: false);

      await openDialog(tester, spaces: []);

      expect(
        find.text('This room is already in all your spaces.'),
        findsOneWidget,
      );
    });

    testWidgets('selection enables Add button', (tester) async {
      final space1 = makeSpace('!s1:x', 'Space A');
      await openDialog(tester, spaces: [space1], hasListView: true);

      final addButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(addButton.onPressed, isNull);

      await tester.tap(find.text('Space A'));
      await tester.pump();

      final addButton2 = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(addButton2.onPressed, isNotNull);
    });

    testWidgets('suggested switch enabled only when space selected',
        (tester) async {
      final space1 = makeSpace('!s1:x', 'Space A');
      await openDialog(tester, spaces: [space1], hasListView: true);

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.onChanged, isNull);

      await tester.tap(find.text('Space A'));
      await tester.pump();

      final switchWidget2 = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget2.onChanged, isNotNull);
    });

    testWidgets('submit calls setSpaceChild with suggested flag',
        (tester) async {
      final space1 = makeSpace('!s1:x', 'Space A');
      await openDialog(tester, spaces: [space1], hasListView: true);

      await tester.tap(find.text('Space A'));
      await tester.pump();

      await tester.tap(find.byType(Switch));
      await tester.pump();

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verify(space1.setSpaceChild('!room:example.com', suggested: true))
          .called(1);
      verify(mockMatrix.invalidateSpaceTree()).called(1);
    });

    testWidgets('partial failure shows SnackBar', (tester) async {
      final space1 = makeSpace('!s1:x', 'Space A');
      when(space1.setSpaceChild(any, suggested: anyNamed('suggested')))
          .thenThrow(Exception('fail'));

      await openDialog(tester, spaces: [space1], hasListView: true);

      await tester.tap(find.text('Space A'));
      await tester.pump();

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Failed to add room to 1 space(s)'), findsOneWidget);
    });

    testWidgets('cancel closes without side effects', (tester) async {
      final space1 = makeSpace('!s1:x', 'Space A');
      await openDialog(tester, spaces: [space1], hasListView: true);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Add to space'), findsNothing);
      verifyNever(
        space1.setSpaceChild(any, suggested: anyNamed('suggested')),
      );
    });
  });
}

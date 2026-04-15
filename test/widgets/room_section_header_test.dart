import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:kohera/features/rooms/widgets/room_section_header.dart';
import 'package:kohera/features/spaces/widgets/space_reparent_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<PreferencesService>(),
  MockSpec<Room>(),
])
import 'room_section_header_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;
  late MockPreferencesService mockPrefs;
  late MockRoom mockSpaceRoom;
  late SpaceReparentController reparentController;
  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    mockPrefs = MockPreferencesService();
    mockSpaceRoom = MockRoom();
    reparentController = SpaceReparentController();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockPrefs.collapsedSpaceSections).thenReturn(<String>{});
    when(mockSpaceRoom.id).thenReturn('!space:example.com');
    when(mockSpaceRoom.canChangeStateEvent(any)).thenReturn(true);
    when(mockClient.getRoomById('!space:example.com'))
        .thenReturn(mockSpaceRoom);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);
    selectionService = SelectionService(client: mockClient);
    when(mockMatrix.selection).thenReturn(selectionService);
  });

  Widget buildTestWidget({
    HeaderItem? item,
  }) {
    final headerItem = item ??
        HeaderItem(
          name: 'Test Space',
          sectionKey: '!space:example.com',
          depth: 0,
          roomCount: 3,
          isSpace: true,
        );
    return ChangeNotifierProvider<SpaceReparentController>.value(
      value: reparentController,
      child: MaterialApp(
        home: Scaffold(
          body: RoomSectionHeader(
            item: headerItem,
            prefs: mockPrefs,
            selection: selectionService,
            matrixService: mockMatrix,
          ),
        ),
      ),
    );
  }

  group('Popup menu', () {
    testWidgets('+ button shows popup with "Create room" and "Create subspace"',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Find and tap the + button.
      final addButton = find.byIcon(Icons.add_rounded);
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Both menu items should be visible.
      expect(find.text('Create room'), findsOneWidget);
      expect(find.text('Create subspace'), findsOneWidget);
    });

    testWidgets('+ button tooltip is "Add to space"', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Add to space');
    });

    testWidgets('+ button not shown when canChangeStateEvent is false',
        (tester) async {
      when(mockSpaceRoom.canChangeStateEvent(any)).thenReturn(false);
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.add_rounded), findsNothing);
    });

    testWidgets('+ button not shown for non-space headers', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        item: HeaderItem(
          name: 'DMs',
          sectionKey: 'dms',
          depth: 0,
          roomCount: 5,
        ),
      ),);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
    });
  });

  group('DragTarget', () {
    testWidgets('highlights header when hovered by drag', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Simulate the controller setting hover state.
      reparentController.setHoveredHeader('!space:example.com');
      await tester.pump(const Duration(milliseconds: 200));

      // The AnimatedContainer should have primaryContainer color.
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer).first,
      );
      final decoration = animatedContainer.decoration! as BoxDecoration;
      expect(decoration.color, isNot(Colors.transparent));
    });

    testWidgets('no DragTarget wrapper for non-space headers', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        item: HeaderItem(
          name: 'Rooms',
          sectionKey: 'unsorted',
          depth: 0,
          roomCount: 2,
        ),
      ),);
      expect(find.byType(DragTarget<ReparentDragData>), findsNothing);
    });

    testWidgets('DragTarget present for space headers', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(DragTarget<ReparentDragData>), findsOneWidget);
    });
  });
}

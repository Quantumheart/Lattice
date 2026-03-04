import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/rooms/widgets/room_context_menu.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
])
import 'room_context_menu_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockSpace;
  late MockRoom mockRoom;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockSpace = MockRoom();
    mockRoom = MockRoom();

    when(mockMatrixService.client).thenReturn(mockClient);

    // Default space setup — selected and user has permission
    when(mockSpace.id).thenReturn('!space:example.com');
    when(mockSpace.getLocalizedDisplayname()).thenReturn('Test Space');
    when(mockSpace.canChangeStateEvent('m.space.child')).thenReturn(true);
    when(mockSpace.removeSpaceChild(any)).thenAnswer((_) async {});

    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');

    when(mockMatrixService.selectedSpaceIds)
        .thenReturn({'!space:example.com'});
    when(mockClient.getRoomById('!space:example.com')).thenReturn(mockSpace);
    when(mockMatrixService.spaceMemberships('!room:example.com'))
        .thenReturn(<String>{});
    when(mockMatrixService.spaces).thenReturn([mockSpace]);
  });

  Widget buildTestWidget() {
    return ChangeNotifierProvider<MatrixService>.value(
      value: mockMatrixService,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showRoomContextMenu(
                  context,
                  const RelativeRect.fromLTRB(100, 100, 100, 100),
                  mockRoom,
                );
              },
              child: const Text('Open Menu'),
            ),
          ),
        ),
      ),
    );
  }

  group('RoomContextMenu', () {
    testWidgets('shows "Remove from space" when space selected and user has permission',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from Test Space'), findsOneWidget);
    });

    testWidgets('shows "Add to space" when eligible spaces exist',
        (tester) async {
      // Room is not in the space yet → "Add to space" shown
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Add to space'), findsOneWidget);
      expect(find.text('Remove from Test Space'), findsOneWidget);
    });

    testWidgets('"Add to space" hidden when room is already in all spaces',
        (tester) async {
      when(mockMatrixService.spaceMemberships('!room:example.com'))
          .thenReturn({'!space:example.com'});

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Add to space'), findsNothing);
      expect(find.text('Remove from Test Space'), findsOneWidget);
    });

    testWidgets('menu hidden when no space selected and no eligible spaces',
        (tester) async {
      when(mockMatrixService.selectedSpaceIds).thenReturn(<String>{});
      when(mockMatrixService.spaceMemberships('!room:example.com'))
          .thenReturn({'!space:example.com'});

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from Test Space'), findsNothing);
      expect(find.text('Add to space'), findsNothing);
    });

    testWidgets('menu hidden when user lacks permission', (tester) async {
      when(mockSpace.canChangeStateEvent('m.space.child')).thenReturn(false);
      when(mockMatrixService.spaces).thenReturn([mockSpace]);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from Test Space'), findsNothing);
      expect(find.text('Add to space'), findsNothing);
    });

    testWidgets('confirmation dialog shown on tap', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove from Test Space'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from space?'), findsOneWidget);
      expect(
        find.textContaining('Remove "Test Room" from "Test Space"'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('confirming calls removeSpaceChild and invalidates tree',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove from Test Space'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      verify(mockSpace.removeSpaceChild('!room:example.com')).called(1);
      verify(mockMatrixService.invalidateSpaceTree()).called(1);
    });

    testWidgets('cancelling does not call removeSpaceChild', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove from Test Space'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(mockSpace.removeSpaceChild(any));
    });
  });
}

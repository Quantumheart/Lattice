import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/rooms/widgets/room_context_menu.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

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

  Widget buildTestWidget({
    String? parentSpaceId,
    List<Room>? sectionRooms,
  }) {
    return ChangeNotifierProvider<MatrixService>.value(
      value: mockMatrixService,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                unawaited(showRoomContextMenu(
                  context,
                  const RelativeRect.fromLTRB(100, 100, 100, 100),
                  mockRoom,
                  parentSpaceId: parentSpaceId,
                  sectionRooms: sectionRooms,
                ));
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

  group('Move Up / Move Down', () {
    late MockRoom mockRoom1;
    late MockRoom mockRoom2;
    late MockRoom mockRoom3;

    setUp(() {
      mockRoom1 = MockRoom();
      mockRoom2 = MockRoom();
      mockRoom3 = MockRoom();

      when(mockRoom1.id).thenReturn('!r1:example.com');
      when(mockRoom1.getLocalizedDisplayname()).thenReturn('Room A');
      when(mockRoom2.id).thenReturn('!r2:example.com');
      when(mockRoom2.getLocalizedDisplayname()).thenReturn('Room B');
      when(mockRoom3.id).thenReturn('!r3:example.com');
      when(mockRoom3.getLocalizedDisplayname()).thenReturn('Room C');

      // Set up space children with order strings
      when(mockSpace.spaceChildren).thenReturn([
        SpaceChild.fromState(StrippedStateEvent(
          type: EventTypes.SpaceChild,
          content: {'via': ['example.com'], 'order': 'a'},
          stateKey: '!r1:example.com',
          senderId: '@admin:example.com',
        ),),
        SpaceChild.fromState(StrippedStateEvent(
          type: EventTypes.SpaceChild,
          content: {'via': ['example.com'], 'order': 'm'},
          stateKey: '!r2:example.com',
          senderId: '@admin:example.com',
        ),),
        SpaceChild.fromState(StrippedStateEvent(
          type: EventTypes.SpaceChild,
          content: {'via': ['example.com'], 'order': 'z'},
          stateKey: '!r3:example.com',
          senderId: '@admin:example.com',
        ),),
      ]);

      when(mockSpace.setSpaceChild(any, order: anyNamed('order')))
          .thenAnswer((_) async {});

      // Use mockRoom (= room B) as the target
      when(mockRoom.id).thenReturn('!r2:example.com');
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room B');
    });

    testWidgets('shows Move up and Move down for middle item', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        parentSpaceId: '!space:example.com',
        sectionRooms: [mockRoom1, mockRoom, mockRoom3],
      ),);
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Move up'), findsOneWidget);
      expect(find.text('Move down'), findsOneWidget);
    });

    testWidgets('hides Move up for first item', (tester) async {
      when(mockRoom.id).thenReturn('!r1:example.com');
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room A');

      await tester.pumpWidget(buildTestWidget(
        parentSpaceId: '!space:example.com',
        sectionRooms: [mockRoom, mockRoom2, mockRoom3],
      ),);
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Move up'), findsNothing);
      expect(find.text('Move down'), findsOneWidget);
    });

    testWidgets('hides Move down for last item', (tester) async {
      when(mockRoom.id).thenReturn('!r3:example.com');
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room C');

      await tester.pumpWidget(buildTestWidget(
        parentSpaceId: '!space:example.com',
        sectionRooms: [mockRoom1, mockRoom2, mockRoom],
      ),);
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Move up'), findsOneWidget);
      expect(find.text('Move down'), findsNothing);
    });

    testWidgets('Move up calls setSpaceChild with correct order',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        parentSpaceId: '!space:example.com',
        sectionRooms: [mockRoom1, mockRoom, mockRoom3],
      ),);
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();

      // Should call setSpaceChild on the space with the room ID and a new
      // order string that is between null (before first) and 'a' (first item).
      final captured = verify(
        mockSpace.setSpaceChild('!r2:example.com',
            order: captureAnyNamed('order'),),
      ).captured;
      expect(captured, hasLength(1));
      final newOrder = captured.first as String;
      // New order should be < 'a' (the order of the item we moved before).
      expect(newOrder.compareTo('a'), lessThan(0));
      verify(mockMatrixService.invalidateSpaceTree()).called(1);
    });

    testWidgets('Move down calls setSpaceChild with correct order',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        parentSpaceId: '!space:example.com',
        sectionRooms: [mockRoom1, mockRoom, mockRoom3],
      ),);
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();

      final captured = verify(
        mockSpace.setSpaceChild('!r2:example.com',
            order: captureAnyNamed('order'),),
      ).captured;
      expect(captured, hasLength(1));
      final newOrder = captured.first as String;
      // New order should be > 'z' (the order of the item we moved after).
      expect(newOrder.compareTo('z'), greaterThan(0));
      verify(mockMatrixService.invalidateSpaceTree()).called(1);
    });

    testWidgets('no Move items when user lacks permission', (tester) async {
      when(mockSpace.canChangeStateEvent('m.space.child')).thenReturn(false);

      await tester.pumpWidget(buildTestWidget(
        parentSpaceId: '!space:example.com',
        sectionRooms: [mockRoom1, mockRoom, mockRoom3],
      ),);
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Move up'), findsNothing);
      expect(find.text('Move down'), findsNothing);
    });

    testWidgets('no Move items when no parentSpaceId', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Move up'), findsNothing);
      expect(find.text('Move down'), findsNothing);
    });
  });
}

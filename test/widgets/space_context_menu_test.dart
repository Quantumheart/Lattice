import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/features/spaces/widgets/space_context_menu.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Event>(),
])
import 'space_context_menu_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockSpace;
  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockSpace = MockRoom();

    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);
    when(mockMatrixService.client).thenReturn(mockClient);
    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);

    // Default space setup — admin with all permissions
    when(mockSpace.id).thenReturn('!space:example.com');
    when(mockSpace.getLocalizedDisplayname()).thenReturn('Test Space');
    when(mockSpace.client).thenReturn(mockClient);
    when(mockSpace.canInvite).thenReturn(true);
    when(mockSpace.canChangeStateEvent(any)).thenReturn(true);
  });

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
        ChangeNotifierProvider<SelectionService>.value(value: selectionService),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                unawaited(showSpaceContextMenu(
                  context,
                  const RelativeRect.fromLTRB(100, 100, 100, 100),
                  mockSpace,
                ),);
              },
              child: const Text('Open Menu'),
            ),
          ),
        ),
      ),
    );
  }

  group('SpaceContextMenu', () {
    testWidgets('shows all items for admin user', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Mark as read'), findsOneWidget);
      expect(find.text('Invite people'), findsOneWidget);
      expect(find.text('Space settings'), findsOneWidget);
      expect(find.text('Create room'), findsOneWidget);
      expect(find.text('Create subspace'), findsOneWidget);
      expect(find.text('Add existing room'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Leave space'), findsOneWidget);
    });

    testWidgets('hides permission-gated items for regular members',
        (tester) async {
      when(mockSpace.canInvite).thenReturn(false);
      when(mockSpace.canChangeStateEvent(any)).thenReturn(false);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      // Always shown
      expect(find.text('Mark as read'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Leave space'), findsOneWidget);

      // Hidden for regular members
      expect(find.text('Invite people'), findsNothing);
      expect(find.text('Space settings'), findsNothing);
      expect(find.text('Create room'), findsNothing);
      expect(find.text('Create subspace'), findsNothing);
      expect(find.text('Add existing room'), findsNothing);
    });

    testWidgets('Leave space is styled with error color', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      final leaveText = tester.widget<Text>(find.text('Leave space'));
      final cs = Theme.of(tester.element(find.text('Leave space'))).colorScheme;
      expect(leaveText.style?.color, cs.error);
    });

    testWidgets('Mark as read calls setReadMarker', (tester) async {
      final mockEvent = MockEvent();
      when(mockEvent.eventId).thenReturn(r'$last:example.com');
      when(mockSpace.lastEvent).thenReturn(mockEvent);
      when(mockSpace.setReadMarker(any)).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();

      verify(mockSpace.setReadMarker(r'$last:example.com')).called(1);
    });

    testWidgets('Leave shows confirmation dialog with checkbox',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave space'));
      await tester.pumpAndSettle();

      expect(find.text('Leave space?'), findsOneWidget);
      expect(
        find.text('You will leave "Test Space".'),
        findsOneWidget,
      );
      expect(
        find.text('Also leave all rooms in this space'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('Confirming leave calls space.leave()', (tester) async {
      when(mockSpace.leave()).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave space'));
      await tester.pumpAndSettle();

      // Tap the "Leave" button in the confirmation dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      verify(mockSpace.leave()).called(1);
      expect(selectionService.selectedSpaceIds, isEmpty);
    });

    testWidgets('Cancelling leave does not call space.leave()',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave space'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(mockSpace.leave());
    });

    testWidgets('Leave with checkbox leaves child rooms too',
        (tester) async {
      // Set up child rooms
      final mockChildRoom = MockRoom();
      when(mockChildRoom.id).thenReturn('!child:example.com');
      when(mockChildRoom.isSpace).thenReturn(false);
      when(mockChildRoom.membership).thenReturn(Membership.join);
      when(mockChildRoom.leave()).thenAnswer((_) async {});

      when(mockClient.getRoomById('!child:example.com'))
          .thenReturn(mockChildRoom);
      when(mockSpace.spaceChildren).thenReturn([
        SpaceChild.fromState(StrippedStateEvent(
          type: EventTypes.SpaceChild,
          content: {'via': ['example.com']},
          stateKey: '!child:example.com',
          senderId: '@admin:example.com',
        ),),
      ]);
      when(mockSpace.leave()).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave space'));
      await tester.pumpAndSettle();

      // Check the checkbox
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      // Confirm leave
      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      verify(mockSpace.leave()).called(1);
      verify(mockChildRoom.leave()).called(1);
      expect(selectionService.selectedSpaceIds, isEmpty);
    });

    testWidgets('Leave without checkbox keeps child rooms',
        (tester) async {
      final mockChildRoom = MockRoom();
      when(mockChildRoom.id).thenReturn('!child:example.com');
      when(mockChildRoom.isSpace).thenReturn(false);
      when(mockChildRoom.membership).thenReturn(Membership.join);

      when(mockClient.getRoomById('!child:example.com'))
          .thenReturn(mockChildRoom);
      when(mockSpace.spaceChildren).thenReturn([
        SpaceChild.fromState(StrippedStateEvent(
          type: EventTypes.SpaceChild,
          content: {'via': ['example.com']},
          stateKey: '!child:example.com',
          senderId: '@admin:example.com',
        ),),
      ]);
      when(mockSpace.leave()).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave space'));
      await tester.pumpAndSettle();

      // Don't check the checkbox, just confirm
      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      verify(mockSpace.leave()).called(1);
      verifyNever(mockChildRoom.leave());
    });

    testWidgets('Space settings navigates to space details route',
        (tester) async {
      // Use a GoRouter-based test widget to verify navigation
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => MultiProvider(
              providers: [
                ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
                ChangeNotifierProvider<SelectionService>.value(value: selectionService),
              ],
              child: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      unawaited(showSpaceContextMenu(
                        context,
                        const RelativeRect.fromLTRB(100, 100, 100, 100),
                        mockSpace,
                      ),);
                    },
                    child: const Text('Open Menu'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/spaces/:spaceId/details',
            name: 'space-details',
            builder: (context, state) => Scaffold(
              body: Text('Space details for ${state.pathParameters['spaceId']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Space settings'));
      await tester.pumpAndSettle();

      expect(find.text('Space details for !space:example.com'), findsOneWidget);
    });

    testWidgets('Notifications item opens notification dialog',
        (tester) async {
      when(mockSpace.pushRuleState).thenReturn(PushRuleState.notify);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      // Notifications item is shown and enabled (tapping opens dialog).
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Space notifications'), findsOneWidget);
      expect(find.text('All messages'), findsOneWidget);
      expect(find.text('Mentions only'), findsOneWidget);
      expect(find.text('Muted'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Selecting a push rule and saving calls setPushRuleState',
        (tester) async {
      when(mockSpace.pushRuleState).thenReturn(PushRuleState.notify);
      when(mockSpace.setPushRuleState(any)).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      // Select "Muted"
      await tester.tap(find.text('Muted'));
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verify(mockSpace.setPushRuleState(PushRuleState.dontNotify)).called(1);
      // Success snackbar shown
      expect(find.text('Notifications updated'), findsOneWidget);
    });

    testWidgets('Cancelling notification dialog does not call setPushRuleState',
        (tester) async {
      when(mockSpace.pushRuleState).thenReturn(PushRuleState.notify);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(mockSpace.setPushRuleState(any));
    });

    testWidgets('Saving unchanged push rule does not call setPushRuleState',
        (tester) async {
      when(mockSpace.pushRuleState).thenReturn(PushRuleState.notify);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      // Save without changing the selection
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verifyNever(mockSpace.setPushRuleState(any));
    });

    testWidgets('Notification error shows failure snackbar',
        (tester) async {
      when(mockSpace.pushRuleState).thenReturn(PushRuleState.notify);
      when(mockSpace.setPushRuleState(any))
          .thenThrow(Exception('network error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Muted'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Failed to update notifications'),
        findsOneWidget,
      );
    });
  });
}

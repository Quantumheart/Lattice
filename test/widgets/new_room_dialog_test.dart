import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/features/rooms/widgets/new_room_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
])
import 'new_room_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;

  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);
    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                unawaited(NewRoomDialog.show(context, matrixService: mockMatrixService));
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('NewRoomDialog', () {
    testWidgets('shows name required error when submitting empty',
        (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
    });

    testWidgets('calls createRoom with correct parameters', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        visibility: anyNamed('visibility'),
        initialState: anyNamed('initialState'),
        invite: anyNamed('invite'),
      ),).thenAnswer((_) async => '!newroom:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Test Room',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Topic (optional)'),
        'A test topic',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(mockClient.createRoom(
        name: 'Test Room',
        topic: 'A test topic',
        visibility: Visibility.private,
        initialState: anyNamed('initialState'),
      ),).called(1);
      verify(mockClient.waitForRoomInSync('!newroom:example.com', join: true))
          .called(1);
      expect(selectionService.selectedRoomId, '!newroom:example.com');
    });

    testWidgets('shows network error on failure', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        visibility: anyNamed('visibility'),
        initialState: anyNamed('initialState'),
        invite: anyNamed('invite'),
      ),).thenThrow(Exception('Server error'));
      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Test Room',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Dialog should still be open with error
      expect(find.text('New Room'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New Room'), findsNothing);
    });

    testWidgets('public room toggle changes visibility', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        visibility: anyNamed('visibility'),
        initialState: anyNamed('initialState'),
        invite: anyNamed('invite'),
      ),).thenAnswer((_) async => '!newroom:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

      await openDialog(tester);

      // Toggle public room switch
      await tester.tap(find.text('Public room'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Public Room',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(mockClient.createRoom(
        name: 'Public Room',
        visibility: Visibility.public,
        initialState: anyNamed('initialState'),
      ),).called(1);
    });

    testWidgets('invite chips can be added and removed', (tester) async {
      await openDialog(tester);

      // Add an invite
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite users (optional)'),
        '@alice:example.com',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('@alice:example.com'), findsOneWidget);

      // Remove it via chip delete
      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, '@alice:example.com'), findsNothing);
    });
  });
}

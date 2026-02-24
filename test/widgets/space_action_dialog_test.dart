import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/space_action_dialog.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
])
import 'space_action_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    when(mockMatrixService.client).thenReturn(mockClient);
  });

  group('CreateSpaceDialog', () {
    Widget buildTestWidget() {
      return MaterialApp(
        home: ChangeNotifierProvider<MatrixService>.value(
          value: mockMatrixService,
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CreateSpaceDialog.show(
                  context,
                  matrixService: mockMatrixService,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows name and topic fields', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Create Space'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Topic (optional)'), findsOneWidget);
    });

    testWidgets('shows toggle switches', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Public space'), findsOneWidget);
      expect(find.text('Enable encryption'), findsOneWidget);
      expect(find.text('Allow federation'), findsOneWidget);
    });

    testWidgets('validates empty name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
    });

    testWidgets('submitting calls client.createRoom and selects space', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        initialState: anyNamed('initialState'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      )).thenAnswer((_) async => '!newspace:example.com');

      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'My Space');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      verify(mockClient.createRoom(
        name: 'My Space',
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        initialState: anyNamed('initialState'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      )).called(1);

      verify(mockMatrixService.selectSpace('!newspace:example.com')).called(1);
    });

    testWidgets('shows error on failure', (tester) async {
      when(mockClient.createRoom(
        name: anyNamed('name'),
        topic: anyNamed('topic'),
        creationContent: anyNamed('creationContent'),
        initialState: anyNamed('initialState'),
        visibility: anyNamed('visibility'),
        powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
      )).thenThrow(Exception('Server error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Bad Space');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Server error'), findsOneWidget);
    });

    testWidgets('toggling public disables encryption', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Toggle public space on
      await tester.tap(find.widgetWithText(SwitchListTile, 'Public space'));
      await tester.pumpAndSettle();

      expect(find.text('Not available for public spaces'), findsOneWidget);
    });

    testWidgets('cancel closes dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Create Space'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Create Space'), findsNothing);
    });
  });

  group('JoinSpaceDialog', () {
    Widget buildTestWidget() {
      return MaterialApp(
        home: ChangeNotifierProvider<MatrixService>.value(
          value: mockMatrixService,
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => JoinSpaceDialog.show(
                  context,
                  matrixService: mockMatrixService,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows address field', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Join Space'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Space address'), findsOneWidget);
    });

    testWidgets('validates empty address', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.text('Address is required'), findsOneWidget);
    });

    testWidgets('submitting calls client.joinRoom', (tester) async {
      final mockSpace = MockRoom();
      when(mockSpace.isSpace).thenReturn(true);

      when(mockClient.joinRoom(any))
          .thenAnswer((_) async => '!space:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
      when(mockClient.getRoomById('!space:example.com')).thenReturn(mockSpace);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Space address'),
        '#myspace:example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      verify(mockClient.joinRoom('#myspace:example.com')).called(1);
      verify(mockMatrixService.selectSpace('!space:example.com')).called(1);
    });

    testWidgets('shows error on join failure', (tester) async {
      when(mockClient.joinRoom(any)).thenThrow(Exception('Room not found'));

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Space address'),
        '#bad:example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Room not found'), findsOneWidget);
    });

    testWidgets('cancel closes dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Join Space'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Join Space'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/spaces/widgets/create_subspace_dialog.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
])
import 'create_subspace_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockParentSpace;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockParentSpace = MockRoom();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockParentSpace.getLocalizedDisplayname())
        .thenReturn('Parent Space');
    when(mockParentSpace.id).thenReturn('!parent:example.com');
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => CreateSubspaceDialog.show(
              context,
              matrixService: mockMatrixService,
              parentSpace: mockParentSpace,
            ),
            child: const Text('Open'),
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

  testWidgets('shows name and topic fields with parent space context',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Create subspace'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
    expect(
        find.widgetWithText(TextField, 'Topic (optional)'), findsOneWidget);
    expect(find.textContaining('Parent Space'), findsOneWidget);
  });

  testWidgets('validates empty name', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('submitting calls createRoom and setSpaceChild', (tester) async {
    when(mockClient.createRoom(
      name: anyNamed('name'),
      topic: anyNamed('topic'),
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    )).thenAnswer((_) async => '!subspace:example.com');

    when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
        .thenAnswer((_) async => SyncUpdate(nextBatch: ''));

    await openDialog(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'My Subspace');
    await tester.enterText(
        find.widgetWithText(TextField, 'Topic (optional)'), 'A topic');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    verify(mockClient.createRoom(
      name: 'My Subspace',
      topic: 'A topic',
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    )).called(1);

    verify(mockParentSpace.setSpaceChild('!subspace:example.com')).called(1);
    verify(mockMatrixService.invalidateSpaceTree()).called(1);

    // Dialog should close on success.
    expect(find.text('Create subspace'), findsNothing);
  });

  testWidgets('shows error on failure', (tester) async {
    when(mockClient.createRoom(
      name: anyNamed('name'),
      topic: anyNamed('topic'),
      creationContent: anyNamed('creationContent'),
      visibility: anyNamed('visibility'),
      powerLevelContentOverride: anyNamed('powerLevelContentOverride'),
    )).thenThrow(Exception('Server error'));

    await openDialog(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Bad Subspace');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Server error'), findsOneWidget);
    // Dialog should remain open.
    expect(find.text('Create subspace'), findsOneWidget);
  });

  testWidgets('cancel closes dialog', (tester) async {
    await openDialog(tester);

    expect(find.text('Create subspace'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Create subspace'), findsNothing);
  });
}

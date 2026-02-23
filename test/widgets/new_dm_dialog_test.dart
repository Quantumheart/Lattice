import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/new_dm_dialog.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
])
import 'new_dm_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.rooms).thenReturn([]);
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                NewDirectMessageDialog.show(
                  context,
                  matrixService: mockMatrixService,
                );
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

  group('NewDirectMessageDialog', () {
    testWidgets('shows search field', (tester) async {
      await openDialog(tester);

      expect(find.text('New Direct Message'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Search users'), findsOneWidget);
    });

    testWidgets('start chat button disabled without valid MXID',
        (tester) async {
      await openDialog(tester);

      // FilledButton should be disabled (no valid MXID)
      final button = tester.widget<FilledButton>(find.widgetWithText(
        FilledButton,
        'Start Chat',
      ));
      expect(button.onPressed, isNull);
    });

    testWidgets('start chat button enabled with valid MXID', (tester) async {
      when(mockClient.searchUserDirectory(any, limit: anyNamed('limit')))
          .thenAnswer((_) async => SearchUserDirectoryResponse(
                results: [],
                limited: false,
              ));

      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search users'),
        '@alice:example.com',
      );
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.widgetWithText(
        FilledButton,
        'Start Chat',
      ));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('calls startDirectChat on submit', (tester) async {
      when(mockClient.startDirectChat(
        any,
        enableEncryption: anyNamed('enableEncryption'),
      )).thenAnswer((_) async => '!dm:example.com');
      when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
          .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
      when(mockClient.searchUserDirectory(any, limit: anyNamed('limit')))
          .thenAnswer((_) async => SearchUserDirectoryResponse(
                results: [],
                limited: false,
              ));

      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search users'),
        '@alice:example.com',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start Chat'));
      await tester.pumpAndSettle();

      verify(mockClient.startDirectChat(
        '@alice:example.com',
        enableEncryption: true,
      )).called(1);
      verify(mockMatrixService.selectRoom('!dm:example.com')).called(1);
    });

    testWidgets('shows known contacts when search is empty', (tester) async {
      final mockRoom = MockRoom();
      when(mockRoom.isDirectChat).thenReturn(true);
      when(mockRoom.directChatMatrixID).thenReturn('@bob:example.com');
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Bob');
      when(mockRoom.avatar).thenReturn(null);
      when(mockClient.rooms).thenReturn([mockRoom]);

      await openDialog(tester);

      expect(find.text('Recent contacts'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New Direct Message'), findsNothing);
    });

    testWidgets('shows error on startDirectChat failure', (tester) async {
      when(mockClient.startDirectChat(
        any,
        enableEncryption: anyNamed('enableEncryption'),
      )).thenThrow(Exception('User not found'));

      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search users'),
        '@invalid:example.com',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start Chat'));
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(find.text('New Direct Message'), findsOneWidget);
    });
  });
}

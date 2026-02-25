import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/invite_dialog.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
])
import 'invite_dialog_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;
  late MockRoom mockRoom;
  late MockClient mockClient;

  setUp(() {
    mockMatrix = MockMatrixService();
    mockRoom = MockRoom();
    mockClient = MockClient();
    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.isSpace).thenReturn(false);
    when(mockRoom.getState(EventTypes.RoomMember, '@me:example.com'))
        .thenReturn(null);
    when(mockMatrix.inviterDisplayName(mockRoom)).thenReturn('Alice');
  });

  Widget buildTestWidget() {
    return ChangeNotifierProvider<MatrixService>.value(
      value: mockMatrix,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => InviteDialog.show(context, room: mockRoom),
                child: const Text('Open'),
              ),
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

  group('InviteDialog', () {
    testWidgets('shows room name and inviter', (tester) async {
      await openDialog(tester);

      expect(find.text('Room invite'), findsOneWidget);
      expect(find.text('Test Room'), findsOneWidget);
      expect(find.text('Invited by Alice'), findsOneWidget);
    });

    testWidgets('shows "Space invite" title for spaces', (tester) async {
      when(mockRoom.isSpace).thenReturn(true);
      await openDialog(tester);

      expect(find.text('Space invite'), findsOneWidget);
    });

    testWidgets('accept calls join and closes dialog', (tester) async {
      when(mockRoom.join()).thenAnswer((_) async => '');
      await openDialog(tester);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      verify(mockRoom.join()).called(1);
      // Dialog should be closed
      expect(find.text('Room invite'), findsNothing);
    });

    testWidgets('accept shows error on failure', (tester) async {
      when(mockRoom.join()).thenThrow(Exception('Server error'));
      await openDialog(tester);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      // Dialog should still be open with error
      expect(find.text('Room invite'), findsOneWidget);
      expect(find.textContaining('Server error'), findsOneWidget);
    });

    testWidgets('decline shows confirmation then calls leave', (tester) async {
      when(mockRoom.leave()).thenAnswer((_) async {});
      await openDialog(tester);

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Decline invite'), findsOneWidget);
      expect(find.text('Decline invite to Test Room?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await tester.pumpAndSettle();

      verify(mockRoom.leave()).called(1);
      // Both dialogs should be closed
      expect(find.text('Room invite'), findsNothing);
    });

    testWidgets('decline cancellation keeps dialog open', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      // Cancel the confirmation
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Original dialog should still be open
      expect(find.text('Room invite'), findsOneWidget);
      verifyNever(mockRoom.leave());
    });

    testWidgets('decline shows error on failure', (tester) async {
      when(mockRoom.leave()).thenThrow(Exception('Network error'));
      await openDialog(tester);

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await tester.pumpAndSettle();

      // Dialog should still be open with error
      expect(find.text('Room invite'), findsOneWidget);
      expect(find.textContaining('Network error'), findsOneWidget);
    });

    testWidgets('buttons are disabled during accept', (tester) async {
      final completer = Completer<String>();
      when(mockRoom.join()).thenAnswer((_) => completer.future);
      await openDialog(tester);

      await tester.tap(find.text('Accept'));
      await tester.pump();

      // Progress indicator should show
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Decline button should be disabled
      final declineButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Decline'),
      );
      expect(declineButton.onPressed, isNull);

      // Complete the future to avoid pending timers
      completer.complete('');
      await tester.pumpAndSettle();
    });
  });
}

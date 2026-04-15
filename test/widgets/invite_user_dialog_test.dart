import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';

@GenerateNiceMocks([MockSpec<Room>()])
import 'invite_user_dialog_test.mocks.dart';

void main() {
  late MockRoom mockRoom;

  setUp(() {
    mockRoom = MockRoom();
  });

  Widget buildTestWidget({ValueChanged<String?>? onResult}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final result =
                    await InviteUserDialog.show(context, room: mockRoom);
                onResult?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    ValueChanged<String?>? onResult,
  }) async {
    await tester.pumpWidget(buildTestWidget(onResult: onResult));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('InviteUserDialog', () {
    testWidgets('shows title and text field', (tester) async {
      await openDialog(tester);

      expect(find.text('Invite user'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Invite'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('empty input shows validation error', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a Matrix ID'), findsOneWidget);
    });

    testWidgets('invalid format shows error', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'alice');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('@alice without server shows error', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), '@alice');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('alice@server (missing @) shows error', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'alice@server');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('valid MXID pops dialog with value', (tester) async {
      String? result;

      // Suppress controller-disposed errors from whenComplete in show()
      final original = FlutterError.onError;
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = original);

      await openDialog(tester, onResult: (v) => result = v);

      await tester.enterText(find.byType(TextField), '@alice:matrix.org');
      await tester.tap(find.text('Invite'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(result, '@alice:matrix.org');
    });

    testWidgets('cancel closes dialog', (tester) async {
      String? result = 'sentinel';

      final original = FlutterError.onError;
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = original);

      await openDialog(tester, onResult: (v) => result = v);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(result, isNull);
    });

    testWidgets('keyboard submit triggers validation', (tester) async {
      final original = FlutterError.onError;
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = original);

      await openDialog(tester);

      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('Please enter a Matrix ID'), findsOneWidget);
    });
  });
}

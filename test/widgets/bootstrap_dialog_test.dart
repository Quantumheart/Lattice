import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/encryption.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/bootstrap_dialog.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Encryption>(),
  MockSpec<Bootstrap>(),
  MockSpec<OpenSSSS>(),
])
import 'bootstrap_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockEncryption mockEncryption;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockEncryption = MockEncryption();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.encryption).thenReturn(mockEncryption);

    // Provide defaults for the sync-waiting calls in _startBootstrap.
    when(mockClient.roomsLoading).thenAnswer((_) async {});
    when(mockClient.accountDataLoading).thenAnswer((_) async {});
    when(mockClient.userDeviceKeysLoading).thenAnswer((_) async {});
    when(mockClient.prevBatch).thenReturn('fake_batch_token');
    when(mockClient.updateUserDeviceKeys()).thenAnswer((_) async {});
  });

  Widget buildTestWidget({bool wipeExisting = false}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => BootstrapDialog(
                    matrixService: mockMatrixService,
                    wipeExisting: wipeExisting,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester,
      {bool wipeExisting = false}) async {
    await tester.pumpWidget(buildTestWidget(wipeExisting: wipeExisting));
    await tester.tap(find.text('Open'));
    // Pump twice: once for the dialog to appear, once for the async
    // _startBootstrap to complete and call encryption.bootstrap().
    await tester.pump();
    await tester.pump();
  }

  group('BootstrapDialog', () {
    testWidgets('shows error when encryption is null', (tester) async {
      when(mockClient.encryption).thenReturn(null);
      await openDialog(tester);

      expect(find.text('Encryption is not available'), findsOneWidget);
      expect(find.text('Backup error'), findsOneWidget);
    });

    testWidgets('_saveToDevice defaults to false', (tester) async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
      when(mockBootstrap.newSsss()).thenAnswer((_) async {});
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.recoveryKey).thenReturn('EsTc ABCD 1234 5678');

      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, isFalse);
    });

    testWidgets('shows generating spinner before key is ready', (tester) async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
      // Use a Completer so we can resolve it to avoid pending timer errors
      final completer = Completer<void>();
      when(mockBootstrap.newSsss()).thenAnswer((_) => completer.future);
      when(mockBootstrap.newSsssKey).thenReturn(null);

      onUpdateCb(mockBootstrap);
      await tester.pump();
      await tester.pump();

      expect(find.text('Generating recovery key...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the future to avoid pending timer assertion
      completer.complete();
      await tester.pump();
    });

    testWidgets('recovery key displayed after generation completes',
        (tester) async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
      when(mockBootstrap.newSsss()).thenAnswer((_) async {});
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.recoveryKey).thenReturn('EsTc ABCD 1234 5678');

      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      expect(find.text('EsTc ABCD 1234 5678'), findsOneWidget);
      expect(find.text('Save your recovery key'), findsOneWidget);
    });

    testWidgets('error state shown when newSsss() throws', (tester) async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
      when(mockBootstrap.newSsss()).thenThrow(Exception('key gen failed'));

      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      expect(find.text('Backup error'), findsOneWidget);
      expect(find.textContaining('Failed to generate recovery key'),
          findsOneWidget);
    });

    testWidgets('save-to-device checkbox present in existing-key unlock flow',
        (tester) async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });
      when(mockMatrixService.getStoredRecoveryKey())
          .thenAnswer((_) async => null);

      await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);

      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      expect(find.text('Enter recovery key'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(find.text('Save to device'), findsOneWidget);
    });

    testWidgets('done state pops dialog', (tester) async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });
      when(mockMatrixService.checkChatBackupStatus())
          .thenAnswer((_) async {});

      await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.done);

      onUpdateCb(mockBootstrap);
      await tester.pump();

      expect(find.text('Done'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(BootstrapDialog), findsNothing);
    });

    testWidgets('lost-key flow restarts in-place', (tester) async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });
      when(mockMatrixService.getStoredRecoveryKey())
          .thenAnswer((_) async => null);

      await openDialog(tester);

      // Move to openExistingSsss state
      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      // Tap "I lost my recovery key"
      await tester.tap(find.text('I lost my recovery key'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Lost recovery key?'), findsOneWidget);

      // Tap "Create new backup" - this pops the confirmation dialog,
      // resets state, and restarts bootstrap (which shows a loading spinner).
      await tester.tap(find.text('Create new backup'));
      // Pump several frames to allow the confirmation dialog to animate out
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The bootstrap dialog should still be showing (restarted in-place)
      expect(find.byType(BootstrapDialog), findsOneWidget);
    });

    testWidgets('clipboard cleared on dispose', (tester) async {
      // Track clipboard calls via the test platform channel
      final clipboardCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final text =
                (methodCall.arguments as Map)['text'] as String? ?? '';
            clipboardCalls.add(text);
          }
          return null;
        },
      );

      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
      when(mockBootstrap.newSsss()).thenAnswer((_) async {});
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.recoveryKey).thenReturn('SECRET_KEY_123');

      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      // Close dialog (cancel) which triggers dispose
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Verify that clipboard was cleared (empty string set) during dispose
      expect(clipboardCalls, contains(''));

      // Restore default handler
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
  });
}

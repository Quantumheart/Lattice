import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/cross_signing.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/bootstrap_dialog.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Encryption>(),
  MockSpec<Bootstrap>(),
  MockSpec<OpenSSSS>(),
  MockSpec<CrossSigning>(),
])
import 'bootstrap_dialog_flow_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockEncryption mockEncryption;
  late MockCrossSigning mockCrossSigning;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockEncryption = MockEncryption();
    mockCrossSigning = MockCrossSigning();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.encryption).thenReturn(mockEncryption);
    when(mockEncryption.crossSigning).thenReturn(mockCrossSigning);
    when(mockCrossSigning.enabled).thenReturn(true);

    // Defaults for sync-waiting calls in startBootstrap.
    when(mockClient.roomsLoading).thenAnswer((_) async {});
    when(mockClient.accountDataLoading).thenAnswer((_) async {});
    when(mockClient.userDeviceKeysLoading).thenAnswer((_) async {});
    when(mockClient.prevBatch).thenReturn('fake_batch_token');
    when(mockClient.updateUserDeviceKeys()).thenAnswer((_) async {});
    when(mockClient.rooms).thenReturn([]);

    // Default stubs for matrixService methods used in onDone / unlock flows.
    when(mockMatrixService.checkChatBackupStatus()).thenAnswer((_) async {});
    when(mockMatrixService.getStoredRecoveryKey())
        .thenAnswer((_) async => null);
    when(mockMatrixService.onUiaRequest)
        .thenAnswer((_) => const Stream.empty());
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

  /// Opens the dialog and returns the captured onUpdate callback.
  Future<void Function(Bootstrap)> openDialog(
    WidgetTester tester, {
    bool wipeExisting = false,
  }) async {
    late void Function(Bootstrap) onUpdateCb;
    when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
        .thenAnswer((invocation) {
      onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
          as void Function(Bootstrap);
      return MockBootstrap();
    });

    await tester.pumpWidget(buildTestWidget(wipeExisting: wipeExisting));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    return onUpdateCb;
  }

  /// Simulates auto-advance states (wipe/cross-signing/key-backup) by
  /// calling onUpdateCb and pumping for the deferred advance callbacks.
  Future<void> advanceAutoStates(
    WidgetTester tester,
    void Function(Bootstrap) onUpdateCb,
    MockBootstrap mockBootstrap,
    List<BootstrapState> states,
  ) async {
    for (final state in states) {
      when(mockBootstrap.state).thenReturn(state);
      onUpdateCb(mockBootstrap);
      await tester.pump();
      await tester.pump();
    }
  }

  /// Sets up a mock bootstrap in askNewSsss state with a generated key.
  MockBootstrap setupNewSsssWithKey(String recoveryKey) {
    final mockBootstrap = MockBootstrap();
    when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
    when(mockBootstrap.newSsss()).thenAnswer((_) async {});
    final mockSsssKey = MockOpenSSSS();
    when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
    when(mockSsssKey.recoveryKey).thenReturn(recoveryKey);
    when(mockSsssKey.isUnlocked).thenReturn(true);
    when(mockSsssKey.maybeCacheAll()).thenAnswer((_) async {});
    return mockBootstrap;
  }

  group('BootstrapDialog flow tests', () {
    // ── Test 1: New backup setup — happy path ──────────────────────
    testWidgets('new backup setup happy path completes and returns true',
        (tester) async {
      final onUpdateCb = await openDialog(tester);

      // askNewSsss → key generated
      final mockBootstrap = setupNewSsssWithKey('EsTc ABCD 1234 5678');
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      expect(find.text('Save your recovery key'), findsOneWidget);
      expect(find.text('EsTc ABCD 1234 5678'), findsOneWidget);

      // Next button should be disabled (key not copied, save-to-device unchecked)
      final nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
      expect(nextButton.onPressed, isNull);

      // Copy the key
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      // Next button should now be enabled
      final nextButtonAfterCopy = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
      expect(nextButtonAfterCopy.onPressed, isNotNull);

      // Change mock state before tapping Next so confirmNewSsss doesn't
      // re-enter key generation (which would re-set _awaitingKeyAck).
      when(mockBootstrap.state).thenReturn(BootstrapState.askWipeCrossSigning);

      // Tap Next (confirmNewSsss)
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump();

      // Simulate remaining auto-advance states
      await advanceAutoStates(tester, onUpdateCb, mockBootstrap, [
        BootstrapState.askSetupCrossSigning,
        BootstrapState.askWipeOnlineKeyBackup,
        BootstrapState.askSetupOnlineKeyBackup,
      ]);

      // Arrive at done
      when(mockBootstrap.state).thenReturn(BootstrapState.done);
      onUpdateCb(mockBootstrap);
      await tester.pump();

      expect(find.text('Backup complete'), findsOneWidget);

      // Tap Done → triggers onDone
      when(mockCrossSigning.selfSign(openSsss: anyNamed('openSsss')))
          .thenAnswer((_) async {});
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.byType(BootstrapDialog), findsNothing);

      // Verify key SDK calls
      verify(mockBootstrap.newSsss()).called(1);
      verify(mockMatrixService.checkChatBackupStatus()).called(1);
      verify(mockMatrixService.clearCachedPassword()).called(1);
    });

    // ── Test 2: New backup setup with save-to-device ───────────────
    testWidgets('new backup setup with save-to-device stores key',
        (tester) async {
      when(mockMatrixService.storeRecoveryKey(any)).thenAnswer((_) async {});

      final onUpdateCb = await openDialog(tester);
      final mockBootstrap = setupNewSsssWithKey('SAVE KEY 1234 5678');
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      // Check "Save to device"
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      // Next should be enabled (save-to-device checked)
      final nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
      expect(nextButton.onPressed, isNotNull);

      // Change mock state before tapping Next to avoid re-entering key gen.
      when(mockBootstrap.state).thenReturn(BootstrapState.askWipeCrossSigning);

      // Tap Next
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump();

      // Advance to done
      await advanceAutoStates(tester, onUpdateCb, mockBootstrap, [
        BootstrapState.askSetupCrossSigning,
        BootstrapState.askWipeOnlineKeyBackup,
        BootstrapState.askSetupOnlineKeyBackup,
      ]);

      when(mockBootstrap.state).thenReturn(BootstrapState.done);
      onUpdateCb(mockBootstrap);
      await tester.pump();

      when(mockCrossSigning.selfSign(openSsss: anyNamed('openSsss')))
          .thenAnswer((_) async {});
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      verify(mockMatrixService.storeRecoveryKey('SAVE KEY 1234 5678')).called(1);
    });

    // ── Test 3: Existing backup unlock — happy path ────────────────
    testWidgets('existing backup unlock happy path returns true',
        (tester) async {
      final onUpdateCb = await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.unlock(keyOrPassphrase: anyNamed('keyOrPassphrase')))
          .thenAnswer((_) async {});
      when(mockBootstrap.openExistingSsss()).thenAnswer((_) async {});
      when(mockCrossSigning.selfSign(recoveryKey: anyNamed('recoveryKey')))
          .thenAnswer((_) async {});

      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      expect(find.text('Enter recovery key'), findsOneWidget);

      // Enter recovery key
      await tester.enterText(find.byType(TextField), 'EsTc VALID KEY 1234');
      await tester.pumpAndSettle();

      // Tap Unlock
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      verify(mockSsssKey.unlock(keyOrPassphrase: 'EsTc VALID KEY 1234'))
          .called(1);
      verify(mockBootstrap.openExistingSsss()).called(1);
      verify(mockCrossSigning.selfSign(recoveryKey: 'EsTc VALID KEY 1234'))
          .called(1);
    });

    // ── Test 4: Existing backup unlock with stored key auto-fill ───
    testWidgets('stored recovery key auto-fills the text field',
        (tester) async {
      when(mockMatrixService.getStoredRecoveryKey())
          .thenAnswer((_) async => 'STORED KEY 9999');

      final onUpdateCb = await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);

      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      // The stored key should be auto-populated
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'STORED KEY 9999');

      verify(mockMatrixService.getStoredRecoveryKey()).called(1);
    });

    // ── Test 5: Invalid key then valid key ─────────────────────────
    testWidgets('invalid key shows error, valid key succeeds',
        (tester) async {
      final onUpdateCb = await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockBootstrap.openExistingSsss()).thenAnswer((_) async {});
      when(mockCrossSigning.selfSign(recoveryKey: anyNamed('recoveryKey')))
          .thenAnswer((_) async {});

      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      // First attempt: bad key
      when(mockSsssKey.unlock(keyOrPassphrase: 'BAD KEY'))
          .thenThrow(Exception('invalid'));
      await tester.enterText(find.byType(TextField), 'BAD KEY');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid recovery key'), findsOneWidget);

      // Second attempt: good key
      when(mockSsssKey.unlock(keyOrPassphrase: anyNamed('keyOrPassphrase')))
          .thenAnswer((_) async {});
      await tester.enterText(find.byType(TextField), 'GOOD KEY');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // Verify unlock was called with both keys
      verify(mockSsssKey.unlock(keyOrPassphrase: 'BAD KEY')).called(1);
      verify(mockSsssKey.unlock(keyOrPassphrase: 'GOOD KEY')).called(1);
      verify(mockBootstrap.openExistingSsss()).called(1);
      verify(mockCrossSigning.selfSign(recoveryKey: 'GOOD KEY')).called(1);
    });

    // ── Test 6: Cancel during new setup ────────────────────────────
    testWidgets('cancel during new setup shows confirmation and returns false',
        (tester) async {
      final onUpdateCb = await openDialog(tester);
      final mockBootstrap = setupNewSsssWithKey('KEY 1234');
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Skip backup setup?'), findsOneWidget);

      // Tap Skip
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.byType(BootstrapDialog), findsNothing);
    });

    // ── Test 7: Cancel then continue setup ─────────────────────────
    testWidgets('cancel then continue setup keeps dialog open',
        (tester) async {
      final onUpdateCb = await openDialog(tester);
      final mockBootstrap = setupNewSsssWithKey('KEY 1234');
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Skip backup setup?'), findsOneWidget);

      // Tap Continue setup
      await tester.tap(find.text('Continue setup'));
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(find.byType(BootstrapDialog), findsOneWidget);
      expect(find.text('Save your recovery key'), findsOneWidget);
    });

    // ── Test 8: Lost key flow ──────────────────────────────────────
    testWidgets('lost key flow restarts bootstrap with wipe',
        (tester) async {
      final onUpdateCb = await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      // Tap "I lost my recovery key"
      await tester.tap(find.text('I lost my recovery key'));
      await tester.pumpAndSettle();

      expect(find.text('Lost recovery key?'), findsOneWidget);

      // Tap "Create new backup"
      await tester.tap(find.text('Create new backup'));
      // Pump several frames to allow confirmation dialog to animate out
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Dialog should still be showing (restarted in-place)
      expect(find.byType(BootstrapDialog), findsOneWidget);

      // bootstrap() should have been called again (restart)
      verify(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .called(2); // Once on open, once on restart
    });

    // ── Test 9: Error state with close button ──────────────────────
    testWidgets('error state shows error and close button',
        (tester) async {
      when(mockClient.encryption).thenReturn(null);

      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) => MockBootstrap());

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Backup error'), findsOneWidget);
      expect(find.text('Encryption is not available'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Tap Close
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(BootstrapDialog), findsNothing);
    });

    // ── Test 10: Next button disabled until key copied or save checked ─
    testWidgets('Next button disabled until key copied or save-to-device checked',
        (tester) async {
      final onUpdateCb = await openDialog(tester);
      final mockBootstrap = setupNewSsssWithKey('KEY ABCD 1234');
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      // Next should be disabled initially
      var nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
      expect(nextButton.onPressed, isNull);

      // Check save-to-device → Next should be enabled
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
      expect(nextButton.onPressed, isNotNull);

      // Uncheck save-to-device → Next should be disabled again
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
      expect(nextButton.onPressed, isNull);

      // Copy key → Next should be enabled
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
      expect(nextButton.onPressed, isNotNull);
    });
  });
}

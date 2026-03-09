import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/e2ee/widgets/bootstrap_dialog.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/cross_signing.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Encryption>(),
  MockSpec<Bootstrap>(),
  MockSpec<OpenSSSS>(),
  MockSpec<CrossSigning>(),
])
import 'bootstrap_flow_test.mocks.dart';

// ── Tests ─────────────────────────────────────────────────────────────

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

    when(mockClient.roomsLoading).thenAnswer((_) async {});
    when(mockClient.accountDataLoading).thenAnswer((_) async {});
    when(mockClient.userDeviceKeysLoading).thenAnswer((_) async {});
    when(mockClient.prevBatch).thenReturn('fake_batch_token');
    when(mockClient.updateUserDeviceKeys()).thenAnswer((_) async {});
    when(mockClient.rooms).thenReturn([]);

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
                unawaited(showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => BootstrapDialog(
                    matrixService: mockMatrixService,
                    wipeExisting: wipeExisting,
                  ),
                ),);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

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

  // ── Group 1: New Key Bootstrap ──────────────────────────────────

  group('Bootstrap flow — new key setup', () {
    testWidgets('loading shows progress indicator and title',
        (tester) async {
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) => MockBootstrap());

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Setting up backup'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
        'new key: displays recovery key → copy → Next → auto-advances to done',
        (tester) async {
      final onUpdateCb = await openDialog(tester);

      final mockBootstrap = setupNewSsssWithKey('EsTc ABCD 1234 5678');
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      expect(find.text('Save your recovery key'), findsOneWidget);
      expect(find.text('EsTc ABCD 1234 5678'), findsOneWidget);

      final nextButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(nextButton.onPressed, isNull);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(find.text('Copied'), findsOneWidget);

      final nextButtonAfter = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(nextButtonAfter.onPressed, isNotNull);

      when(mockBootstrap.state)
          .thenReturn(BootstrapState.askWipeCrossSigning);
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump();

      await advanceAutoStates(tester, onUpdateCb, mockBootstrap, [
        BootstrapState.askSetupCrossSigning,
        BootstrapState.askWipeOnlineKeyBackup,
        BootstrapState.askSetupOnlineKeyBackup,
      ]);

      when(mockBootstrap.state).thenReturn(BootstrapState.done);
      onUpdateCb(mockBootstrap);
      await tester.pump();

      expect(find.text('Backup complete'), findsOneWidget);

      when(mockCrossSigning.selfSign(openSsss: anyNamed('openSsss')))
          .thenAnswer((_) async {});
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(BootstrapDialog), findsNothing);
      verify(mockBootstrap.newSsss()).called(1);
      verify(mockMatrixService.checkChatBackupStatus()).called(1);
    });
  });

  // ── Group 2: Existing Key Unlock ─────────────────────────────

  group('Bootstrap flow — existing key unlock', () {
    testWidgets('enter recovery key and unlock', (tester) async {
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

      await tester.enterText(find.byType(TextField), 'EsTc VALID KEY 1234');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      verify(mockSsssKey.unlock(keyOrPassphrase: 'EsTc VALID KEY 1234'))
          .called(1);
      verify(mockBootstrap.openExistingSsss()).called(1);
    });

    testWidgets('stored key auto-fills recovery key field',
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

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'STORED KEY 9999');
    });
  });

  // ── Group 3: Cancel Flow ──────────────────────────────────────

  group('Bootstrap flow — cancel', () {
    testWidgets('cancel shows confirmation; Skip dismisses',
        (tester) async {
      final onUpdateCb = await openDialog(tester);
      final mockBootstrap = setupNewSsssWithKey('KEY 1234');
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Skip backup setup?'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.byType(BootstrapDialog), findsNothing);
    });

    testWidgets('cancel then continue keeps dialog open', (tester) async {
      final onUpdateCb = await openDialog(tester);
      final mockBootstrap = setupNewSsssWithKey('KEY 1234');
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue setup'));
      await tester.pumpAndSettle();

      expect(find.byType(BootstrapDialog), findsOneWidget);
      expect(find.text('Save your recovery key'), findsOneWidget);
    });
  });

  // ── Group 4: Lost Key Flow ──────────────────────────────────

  group('Bootstrap flow — lost key', () {
    testWidgets('lost key restarts with wipe', (tester) async {
      final onUpdateCb = await openDialog(tester);

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      onUpdateCb(mockBootstrap);
      await tester.pumpAndSettle();

      await tester.tap(find.text('I lost my recovery key'));
      await tester.pumpAndSettle();

      expect(find.text('Lost recovery key?'), findsOneWidget);

      await tester.tap(find.text('Create new backup'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(BootstrapDialog), findsOneWidget);
      verify(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .called(2);
    });
  });

  // ── Group 5: Error State ──────────────────────────────────────

  group('Bootstrap flow — error', () {
    testWidgets('encryption unavailable shows error immediately',
        (tester) async {
      when(mockClient.encryption).thenReturn(null);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Backup error'), findsOneWidget);
      expect(find.text('Encryption is not available'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('close button dismisses error dialog', (tester) async {
      when(mockClient.encryption).thenReturn(null);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(BootstrapDialog), findsNothing);
    });

    testWidgets('retry resets to loading and restarts', (tester) async {
      when(mockClient.encryption).thenReturn(null);

      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Backup error'), findsOneWidget);

      when(mockClient.encryption).thenReturn(mockEncryption);
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) => MockBootstrap());

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Setting up backup'), findsOneWidget);
    });
  });
}

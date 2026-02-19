
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/encryption.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/bootstrap_controller.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Encryption>(),
  MockSpec<Bootstrap>(),
  MockSpec<OpenSSSS>(),
])
import 'bootstrap_controller_test.mocks.dart';

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

    when(mockClient.roomsLoading).thenAnswer((_) async {});
    when(mockClient.accountDataLoading).thenAnswer((_) async {});
    when(mockClient.userDeviceKeysLoading).thenAnswer((_) async {});
    when(mockClient.prevBatch).thenReturn('fake_batch_token');
    when(mockClient.updateUserDeviceKeys()).thenAnswer((_) async {});
  });

  BootstrapController createController({bool wipeExisting = false}) {
    return BootstrapController(
      matrixService: mockMatrixService,
      wipeExisting: wipeExisting,
    );
  }

  group('BootstrapController', () {
    test('error state when encryption is null', () async {
      when(mockClient.encryption).thenReturn(null);
      final controller = createController();

      await controller.startBootstrap();

      expect(controller.state, BootstrapState.error);
      expect(controller.error, 'Encryption is not available');
      controller.dispose();
    });

    test('deferredAdvance set for askWipeSsss', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askWipeSsss);

      onUpdateCb(mockBootstrap);

      expect(controller.deferredAdvance, isNotNull);
      controller.deferredAdvance!();
      verify(mockBootstrap.wipeSsss(false)).called(1);
      controller.dispose();
    });

    test('deferredAdvance set for askSetupCrossSigning', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state)
          .thenReturn(BootstrapState.askSetupCrossSigning);

      onUpdateCb(mockBootstrap);

      expect(controller.deferredAdvance, isNotNull);
      controller.deferredAdvance!();
      verify(mockBootstrap.askSetupCrossSigning(
        setupMasterKey: true,
        setupSelfSigningKey: true,
        setupUserSigningKey: true,
      )).called(1);
      controller.dispose();
    });

    test('deferredAdvance set for askSetupOnlineKeyBackup', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state)
          .thenReturn(BootstrapState.askSetupOnlineKeyBackup);

      onUpdateCb(mockBootstrap);

      expect(controller.deferredAdvance, isNotNull);
      controller.deferredAdvance!();
      verify(mockBootstrap.askSetupOnlineKeyBackup(true)).called(1);
      controller.dispose();
    });

    test('deferredAdvance set for askBadSsss', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askBadSsss);

      onUpdateCb(mockBootstrap);

      expect(controller.deferredAdvance, isNotNull);
      controller.deferredAdvance!();
      verify(mockBootstrap.ignoreBadSecrets(true)).called(1);
      controller.dispose();
    });

    test('askNewSsss triggers key generation and populates newRecoveryKey',
        () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
      when(mockBootstrap.newSsss()).thenAnswer((_) async {});
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.recoveryKey).thenReturn('EsTc ABCD 1234 5678');

      onUpdateCb(mockBootstrap);
      // Allow the async _generateNewSsssKey to complete
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, BootstrapState.askNewSsss);
      expect(controller.newRecoveryKey, 'EsTc ABCD 1234 5678');
      expect(controller.generatingKey, isFalse);
      controller.dispose();
    });

    test('confirmNewSsss clears gate and re-processes state', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
      when(mockBootstrap.newSsss()).thenAnswer((_) async {});
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.recoveryKey).thenReturn('KEY');

      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      // Now simulate bootstrap advancing to done while gate is closed
      when(mockBootstrap.state).thenReturn(BootstrapState.done);
      controller.confirmNewSsss();

      expect(controller.state, BootstrapState.done);
      controller.dispose();
    });

    test('unlockExistingSsss with empty key sets recoveryKeyError', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockMatrixService.getStoredRecoveryKey())
          .thenAnswer((_) async => null);

      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      await controller.unlockExistingSsss('');

      expect(controller.recoveryKeyError, 'Please enter a recovery key');
      controller.dispose();
    });

    test('unlockExistingSsss with invalid key sets recoveryKeyError',
        () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.unlock(keyOrPassphrase: anyNamed('keyOrPassphrase')))
          .thenThrow(Exception('bad key'));
      when(mockMatrixService.getStoredRecoveryKey())
          .thenAnswer((_) async => null);

      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      await controller.unlockExistingSsss('bad-key');

      expect(controller.recoveryKeyError, 'Invalid recovery key');
      controller.dispose();
    });

    test(
        'unlockExistingSsss with valid key and saveToDevice calls storeRecoveryKey',
        () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.unlock(keyOrPassphrase: anyNamed('keyOrPassphrase')))
          .thenAnswer((_) async {});
      when(mockBootstrap.openExistingSsss()).thenAnswer((_) async {});
      when(mockMatrixService.storeRecoveryKey(any)).thenAnswer((_) async {});
      when(mockMatrixService.getStoredRecoveryKey())
          .thenAnswer((_) async => null);

      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      controller.setSaveToDevice(true);
      await controller.unlockExistingSsss('valid-key');

      verify(mockMatrixService.storeRecoveryKey('valid-key')).called(1);
      controller.dispose();
    });

    test('onDone sets pendingAction to done', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });
      when(mockMatrixService.checkChatBackupStatus())
          .thenAnswer((_) async {});

      final controller = createController();
      await controller.startBootstrap();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.done);
      onUpdateCb(mockBootstrap);

      await controller.onDone();

      expect(controller.pendingAction, BootstrapAction.done);
      controller.dispose();
    });

    test('restartWithWipe resets all state', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final controller = createController();
      await controller.startBootstrap();

      // Move to some non-loading state first
      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      when(mockMatrixService.getStoredRecoveryKey())
          .thenAnswer((_) async => null);
      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, BootstrapState.openExistingSsss);

      controller.restartWithWipe();
      // After restartWithWipe, state should be reset to loading
      // (before startBootstrap completes)
      expect(controller.state, BootstrapState.loading);
      expect(controller.error, isNull);
      expect(controller.newRecoveryKey, isNull);
      expect(controller.generatingKey, isFalse);
      expect(controller.recoveryKeyError, isNull);

      // Wait for startBootstrap to complete
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
    });

    test('title returns correct string per state', () async {
      final controller = createController();

      // Default state is loading
      expect(controller.title, 'Setting up backup');
      controller.dispose();
    });

    test('title for error state', () async {
      when(mockClient.encryption).thenReturn(null);
      final controller = createController();

      await controller.startBootstrap();

      expect(controller.title, 'Backup error');
      controller.dispose();
    });
  });
}

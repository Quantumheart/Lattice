
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/e2ee/widgets/bootstrap_controller.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

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

      expect(controller.phase, SetupPhase.error);
      expect(controller.error, 'Encryption is not available');
      controller.dispose();
    });

    test('auto-advances askWipeSsss via microtask', () async {
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
      await Future<void>.delayed(Duration.zero);

      verify(mockBootstrap.wipeSsss(false)).called(1);
      controller.dispose();
    });

    test('auto-advances askSetupCrossSigning via microtask', () async {
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
      await Future<void>.delayed(Duration.zero);

      verify(mockBootstrap.askSetupCrossSigning(
        setupMasterKey: true,
        setupSelfSigningKey: true,
        setupUserSigningKey: true,
      ),).called(1);
      controller.dispose();
    });

    test('auto-advances askSetupOnlineKeyBackup via microtask', () async {
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
      await Future<void>.delayed(Duration.zero);

      verify(mockBootstrap.askSetupOnlineKeyBackup(true)).called(1);
      controller.dispose();
    });

    test('auto-advances askBadSsss via microtask', () async {
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
      await Future<void>.delayed(Duration.zero);

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
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, SetupPhase.savingKey);
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
      when(mockMatrixService.checkChatBackupStatus())
          .thenAnswer((_) async {});

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

      when(mockBootstrap.state).thenReturn(BootstrapState.done);
      controller.confirmNewSsss();
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, SetupPhase.done);
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

    test('bootstrap done triggers _onDone and sets phase to done', () async {
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
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, SetupPhase.done);
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

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      when(mockMatrixService.getStoredRecoveryKey())
          .thenAnswer((_) async => null);
      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, SetupPhase.unlock);

      controller.restartWithWipe();
      expect(controller.phase, SetupPhase.loading);
      expect(controller.error, isNull);
      expect(controller.newRecoveryKey, isNull);
      expect(controller.generatingKey, isFalse);
      expect(controller.recoveryKeyError, isNull);

      await Future<void>.delayed(Duration.zero);
      controller.dispose();
    });

    test('loadingMessage returns correct string per state', () async {
      final controller = createController();
      expect(controller.loadingMessage, 'Preparing...');
      controller.dispose();
    });
  });
}

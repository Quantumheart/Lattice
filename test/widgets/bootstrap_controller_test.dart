
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/sub_services/chat_backup_service.dart';
import 'package:lattice/core/services/sub_services/uia_service.dart';
import 'package:lattice/features/e2ee/widgets/bootstrap_controller.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<ChatBackupService>(),
  MockSpec<Encryption>(),
  MockSpec<Bootstrap>(),
  MockSpec<OpenSSSS>(),
  MockSpec<UiaService>(),
])
import 'bootstrap_controller_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockChatBackupService mockChatBackup;
  late MockEncryption mockEncryption;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockChatBackup = MockChatBackupService();
    mockEncryption = MockEncryption();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockMatrixService.chatBackup).thenReturn(mockChatBackup);
    when(mockMatrixService.uia).thenReturn(MockUiaService());
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

  group('BootstrapController integration', () {
    test('error state when encryption is null', () async {
      when(mockClient.encryption).thenReturn(null);
      final controller = createController();

      await controller.startBootstrap();

      expect(controller.phase, SetupPhase.error);
      expect(controller.error, 'Encryption is not available');
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
      when(mockChatBackup.checkChatBackupStatus())
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

    test('askNewSsss generates key and sets savingKey phase', () async {
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
      controller.dispose();
    });

    test('phase stays savingKey when bootstrap advances during key gen',
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
      when(mockBootstrap.newSsss()).thenAnswer((_) async {
        when(mockBootstrap.state)
            .thenReturn(BootstrapState.askSetupCrossSigning);
        onUpdateCb(mockBootstrap);
      });
      final mockSsssKey = MockOpenSSSS();
      when(mockBootstrap.newSsssKey).thenReturn(mockSsssKey);
      when(mockSsssKey.recoveryKey).thenReturn('EsTc ABCD 1234 5678');

      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, SetupPhase.savingKey);
      expect(controller.newRecoveryKey, 'EsTc ABCD 1234 5678');
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
      when(mockChatBackup.getStoredRecoveryKey())
          .thenAnswer((_) async => null);
      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, SetupPhase.unlock);

      controller.restartWithWipe();
      expect(controller.phase, SetupPhase.loading);
      expect(controller.error, isNull);
      expect(controller.newRecoveryKey, isNull);

      await Future<void>.delayed(Duration.zero);
      controller.dispose();
    });
  });
}

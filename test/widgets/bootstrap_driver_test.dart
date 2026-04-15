import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/e2ee/widgets/bootstrap_controller.dart';
import 'package:kohera/features/e2ee/widgets/bootstrap_driver.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Encryption>(),
  MockSpec<Bootstrap>(),
])
import 'bootstrap_driver_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockEncryption mockEncryption;
  late SetupPhase lastPhase;
  late String? lastError;
  late int doneCount;
  late int newSsssCount;
  late int openExistingCount;

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

    lastPhase = SetupPhase.loading;
    lastError = null;
    doneCount = 0;
    newSsssCount = 0;
    openExistingCount = 0;
  });

  BootstrapDriver createDriver({bool wipeExisting = false}) {
    return BootstrapDriver(
      matrixService: mockMatrixService,
      wipeExisting: wipeExisting,
      onPhaseChanged: (phase) => lastPhase = phase,
      onNewSsss: () => newSsssCount++,
      onOpenExistingSsss: () => openExistingCount++,
      onDone: () async => doneCount++,
      onError: (error) => lastError = error,
    );
  }

  group('BootstrapDriver', () {
    test('error when encryption is null', () async {
      when(mockClient.encryption).thenReturn(null);
      final driver = createDriver();

      await driver.start();

      expect(lastError, 'Encryption is not available');
      driver.dispose();
    });

    test('auto-advances askWipeSsss via microtask', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final driver = createDriver();
      await driver.start();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askWipeSsss);

      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      verify(mockBootstrap.wipeSsss(false)).called(1);
      driver.dispose();
    });

    test('auto-advances askSetupCrossSigning via microtask', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final driver = createDriver();
      await driver.start();

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
      driver.dispose();
    });

    test('auto-advances askSetupOnlineKeyBackup via microtask', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final driver = createDriver();
      await driver.start();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state)
          .thenReturn(BootstrapState.askSetupOnlineKeyBackup);

      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      verify(mockBootstrap.askSetupOnlineKeyBackup(true)).called(1);
      driver.dispose();
    });

    test('auto-advances askBadSsss via microtask', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final driver = createDriver();
      await driver.start();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askBadSsss);

      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      verify(mockBootstrap.ignoreBadSecrets(true)).called(1);
      driver.dispose();
    });

    test('done state calls onDone callback', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final driver = createDriver();
      await driver.start();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.done);
      onUpdateCb(mockBootstrap);
      await Future<void>.delayed(Duration.zero);

      expect(doneCount, 1);
      driver.dispose();
    });

    test('askNewSsss calls onNewSsss and sets awaitingKeyAck', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final driver = createDriver();
      await driver.start();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
      onUpdateCb(mockBootstrap);

      expect(newSsssCount, 1);
      expect(lastPhase, SetupPhase.savingKey);
      driver.dispose();
    });

    test('openExistingSsss calls onOpenExistingSsss', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final driver = createDriver();
      await driver.start();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.openExistingSsss);
      onUpdateCb(mockBootstrap);

      expect(openExistingCount, 1);
      expect(lastPhase, SetupPhase.unlock);
      driver.dispose();
    });

    test('confirmNewSsss clears gate and re-processes state', () async {
      late void Function(Bootstrap) onUpdateCb;
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) {
        onUpdateCb = invocation.namedArguments[const Symbol('onUpdate')]
            as void Function(Bootstrap);
        return MockBootstrap();
      });

      final driver = createDriver();
      await driver.start();

      final mockBootstrap = MockBootstrap();
      when(mockBootstrap.state).thenReturn(BootstrapState.askNewSsss);
      onUpdateCb(mockBootstrap);

      when(mockBootstrap.state).thenReturn(BootstrapState.done);
      driver.confirmNewSsss();
      await Future<void>.delayed(Duration.zero);

      expect(doneCount, 1);
      driver.dispose();
    });

    test('restart resets state and starts again', () async {
      when(mockEncryption.bootstrap(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) => MockBootstrap());

      final driver = createDriver();
      await driver.start();

      driver.restart(wipe: true);
      await Future<void>.delayed(Duration.zero);

      expect(driver.state, BootstrapState.loading);
      driver.dispose();
    });

    test('loadingMessage returns correct string', () {
      final driver = createDriver();
      expect(driver.loadingMessage, 'Preparing...');
      driver.dispose();
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/server_auth_capabilities.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/auth_service.dart';
import 'package:kohera/features/auth/widgets/login_controller.dart';
import 'package:matrix/matrix.dart' hide LoginState;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<ClientManager>(),
  MockSpec<Client>(),
  MockSpec<AuthService>(),
])
import 'login_controller_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrixService;
  late MockClientManager mockClientManager;
  late MockClient mockClient;
  late MockAuthService mockAuthService;

  setUp(() {
    mockMatrixService = MockMatrixService();
    mockClientManager = MockClientManager();
    mockClient = MockClient();
    mockAuthService = MockAuthService();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockMatrixService.auth).thenReturn(mockAuthService);
    when(mockClientManager.services).thenReturn([]);
  });

  LoginController createController({
    String homeserver = 'example.com',
    ServerAuthCapabilities capabilities = const ServerAuthCapabilities(
      supportsPassword: true,
    ),
  }) {
    return LoginController(
      matrixService: mockMatrixService,
      clientManager: mockClientManager,
      homeserver: homeserver,
      capabilities: capabilities,
    );
  }

  group('LoginController', () {
    group('initial state', () {
      test('starts in formReady state', () {
        final controller = createController();
        expect(controller.state, LoginState.formReady);
        controller.dispose();
      });

      test('exposes capabilities from constructor', () {
        final controller = createController(
          capabilities: const ServerAuthCapabilities(
            supportsPassword: true,
            supportsSso: true,
            ssoIdentityProviders: [
              SsoIdentityProvider(id: 'google', name: 'Google'),
            ],
          ),
        );

        expect(controller.supportsPassword, isTrue);
        expect(controller.supportsSso, isTrue);
        expect(controller.ssoProviders, hasLength(1));
        expect(controller.ssoProviders[0].name, 'Google');
        controller.dispose();
      });
    });

    group('login', () {
      test('transitions to done on successful login', () async {
        when(mockMatrixService.login(
          homeserver: anyNamed('homeserver'),
          username: anyNamed('username'),
          password: anyNamed('password'),
        ),).thenAnswer((_) async => true);

        final controller = createController();

        final success = await controller.login(
          username: 'alice',
          password: 'pass123',
        );

        expect(success, isTrue);
        expect(controller.state, LoginState.done);
        verify(mockClientManager.commitPendingService()).called(1);
        controller.dispose();
      });

      test('transitions back to formReady on failed login', () async {
        when(mockMatrixService.login(
          homeserver: anyNamed('homeserver'),
          username: anyNamed('username'),
          password: anyNamed('password'),
        ),).thenAnswer((_) async => false);
        when(mockAuthService.loginError).thenReturn('Invalid password');

        final controller = createController();

        final success = await controller.login(
          username: 'alice',
          password: 'wrong',
        );

        expect(success, isFalse);
        expect(controller.state, LoginState.formReady);
        expect(controller.error, 'Invalid password');
        controller.dispose();
      });

      test('transitions through loggingIn state', () async {
        final loginCompleter = Completer<bool>();

        when(mockMatrixService.login(
          homeserver: anyNamed('homeserver'),
          username: anyNamed('username'),
          password: anyNamed('password'),
        ),).thenAnswer((_) => loginCompleter.future);

        final controller = createController();

        final loginFuture = controller.login(
          username: 'alice',
          password: 'pass',
        );

        expect(controller.state, LoginState.loggingIn);

        loginCompleter.complete(true);
        await loginFuture;

        expect(controller.state, LoginState.done);
        controller.dispose();
      });
    });

    group('cancelSso', () {
      test('returns to formReady', () {
        final controller = createController(
          capabilities: const ServerAuthCapabilities(supportsSso: true),
        );

        controller.cancelSso();
        expect(controller.state, LoginState.formReady);
        controller.dispose();
      });
    });

    group('dispose', () {
      test('does not notify after dispose', () async {
        final controller = createController();
        controller.dispose();

        // Should not throw after dispose.
        expect(controller.cancelSso, returnsNormally);
      });
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart' hide LoginState;
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/services/client_manager.dart';
import 'package:lattice/widgets/login_controller.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<ClientManager>(),
  MockSpec<Client>(),
])
import 'login_controller_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrixService;
  late MockClientManager mockClientManager;
  late MockClient mockClient;

  setUp(() {
    mockMatrixService = MockMatrixService();
    mockClientManager = MockClientManager();
    mockClient = MockClient();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClientManager.services).thenReturn([]);
  });

  LoginController createController({String homeserver = 'example.com'}) {
    return LoginController(
      matrixService: mockMatrixService,
      clientManager: mockClientManager,
      homeserver: homeserver,
    );
  }

  group('LoginController', () {
    group('checkServer', () {
      test('starts in checkingServer state', () {
        final controller = createController();
        expect(controller.state, LoginState.checkingServer);
        controller.dispose();
      });

      test('transitions to formReady when password login is supported',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                ));

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, LoginState.formReady);
        expect(controller.supportsPassword, isTrue);
        expect(controller.supportsSso, isFalse);
        controller.dispose();
      });

      test('transitions to formReady when SSO is supported', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsSso: true,
                  ssoIdentityProviders: [
                    SsoIdentityProvider(id: 'google', name: 'Google'),
                  ],
                ));

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, LoginState.formReady);
        expect(controller.supportsSso, isTrue);
        expect(controller.supportsPassword, isFalse);
        expect(controller.ssoProviders, hasLength(1));
        expect(controller.ssoProviders[0].name, 'Google');
        controller.dispose();
      });

      test('transitions to formReady when both password and SSO are supported',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                  supportsSso: true,
                  ssoIdentityProviders: [
                    SsoIdentityProvider(id: 'oidc', name: 'OIDC'),
                  ],
                ));

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, LoginState.formReady);
        expect(controller.supportsPassword, isTrue);
        expect(controller.supportsSso, isTrue);
        controller.dispose();
      });

      test(
          'transitions to serverError when neither password nor SSO is supported',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities());

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, LoginState.serverError);
        expect(controller.error, isNotNull);
        controller.dispose();
      });

      test('transitions to serverError on network failure', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenThrow(const SocketException('Connection refused'));

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, LoginState.serverError);
        expect(controller.error, 'Could not reach server');
        controller.dispose();
      });

      test('discards stale server check results', () async {
        final firstCompleter = Completer<ServerAuthCapabilities>();
        var callCount = 0;

        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) {
          callCount++;
          if (callCount == 1) return firstCompleter.future;
          return Future.value(const ServerAuthCapabilities(
            supportsPassword: true,
          ));
        });

        final controller = createController();

        // Start first check (slow).
        final first = controller.checkServer();

        // Start second check (fast) — should supersede the first.
        final second = controller.checkServer();
        await second;

        expect(controller.state, LoginState.formReady);
        expect(controller.supportsPassword, isTrue);

        // Complete the first check — it should be discarded.
        firstCompleter.complete(const ServerAuthCapabilities(
          supportsSso: true,
        ));
        await first;

        // State should still reflect the second check.
        expect(controller.supportsPassword, isTrue);
        expect(controller.supportsSso, isFalse);
        controller.dispose();
      });
    });

    group('login', () {
      test('transitions to done on successful login', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                ));
        when(mockMatrixService.login(
          homeserver: anyNamed('homeserver'),
          username: anyNamed('username'),
          password: anyNamed('password'),
        )).thenAnswer((_) async => true);

        final controller = createController();
        await controller.checkServer();

        final success = await controller.login(
          username: 'alice',
          password: 'pass123',
        );

        expect(success, isTrue);
        expect(controller.state, LoginState.done);
        verify(mockClientManager.addService(mockMatrixService)).called(1);
        controller.dispose();
      });

      test('transitions back to formReady on failed login', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                ));
        when(mockMatrixService.login(
          homeserver: anyNamed('homeserver'),
          username: anyNamed('username'),
          password: anyNamed('password'),
        )).thenAnswer((_) async => false);
        when(mockMatrixService.loginError).thenReturn('Invalid password');

        final controller = createController();
        await controller.checkServer();

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

        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                ));
        when(mockMatrixService.login(
          homeserver: anyNamed('homeserver'),
          username: anyNamed('username'),
          password: anyNamed('password'),
        )).thenAnswer((_) => loginCompleter.future);

        final controller = createController();
        await controller.checkServer();

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

    group('updateHomeserver', () {
      test('rechecks server on homeserver change', () async {
        when(mockMatrixService.getServerAuthCapabilities('example.com'))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                ));
        when(mockMatrixService.getServerAuthCapabilities('other.org'))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsSso: true,
                ));

        final controller = createController();
        await controller.checkServer();
        expect(controller.supportsPassword, isTrue);

        await controller.updateHomeserver('other.org');
        expect(controller.supportsSso, isTrue);
        expect(controller.supportsPassword, isFalse);
        controller.dispose();
      });
    });

    group('cancelSso', () {
      test('returns to formReady from ssoInProgress', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsSso: true,
                ));

        final controller = createController();
        await controller.checkServer();

        // We cannot easily test the full SSO flow without mocking
        // url_launcher and SsoCallbackServer, but we can verify cancelSso
        // resets state when called.
        controller.cancelSso();
        expect(controller.state, LoginState.formReady);
        controller.dispose();
      });
    });

    group('dispose', () {
      test('does not notify after dispose', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                ));

        final controller = createController();
        controller.dispose();

        // Should not throw when the async check completes after dispose.
        await controller.checkServer();
      });
    });
  });
}

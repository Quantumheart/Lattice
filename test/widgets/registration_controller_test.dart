import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/registration_controller.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
])
import 'registration_controller_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    when(mockMatrixService.client).thenReturn(mockClient);
  });

  RegistrationController createController({String homeserver = 'example.com'}) {
    return RegistrationController(
      matrixService: mockMatrixService,
      homeserver: homeserver,
    );
  }

  group('RegistrationController', () {
    group('checkServer', () {
      test('starts in checkingServer state', () {
        final controller = createController();
        expect(controller.state, RegistrationState.checkingServer);
        controller.dispose();
      });

      test('transitions to formReady when registration is supported',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ));

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, RegistrationState.formReady);
        expect(controller.serverReady, isTrue);
        controller.dispose();
      });

      test('transitions to registrationDisabled when server does not support it',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: false,
                ));

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, RegistrationState.registrationDisabled);
        expect(controller.serverReady, isFalse);
        controller.dispose();
      });

      test('transitions to error on network failure', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenThrow(Exception('Connection refused'));

        final controller = createController();
        await controller.checkServer();

        expect(controller.state, RegistrationState.error);
        expect(controller.error, contains('Connection refused'));
        controller.dispose();
      });

      test('notifies listeners on state change', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                ));

        final controller = createController();
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.checkServer();

        expect(notifyCount, greaterThan(0));
        controller.dispose();
      });
    });

    group('updateHomeserver', () {
      test('re-checks server capabilities with new homeserver', () async {
        when(mockMatrixService.getServerAuthCapabilities('example.com'))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                ));
        when(mockMatrixService.getServerAuthCapabilities('other.com'))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: false,
                ));

        final controller = createController();
        await controller.checkServer();
        expect(controller.serverReady, isTrue);

        await controller.updateHomeserver('other.com');
        expect(controller.homeserver, 'other.com');
        expect(controller.state, RegistrationState.registrationDisabled);
        controller.dispose();
      });

      test('clears errors when homeserver changes', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                ));

        final controller = createController();
        await controller.checkServer();

        // Trigger a username error
        await controller.submitForm(username: '', password: 'password123');
        expect(controller.usernameError, isNotNull);

        await controller.updateHomeserver('new.com');
        expect(controller.usernameError, isNull);
        expect(controller.passwordError, isNull);
        expect(controller.error, isNull);
        controller.dispose();
      });
    });

    group('submitForm', () {
      setUp(() {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ));
      });

      test('rejects empty username', () async {
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(username: '', password: 'password123');

        expect(controller.state, RegistrationState.formReady);
        expect(controller.usernameError, isNotNull);
        controller.dispose();
      });

      test('rejects empty password', () async {
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(username: 'user', password: '');

        expect(controller.state, RegistrationState.formReady);
        expect(controller.passwordError, isNotNull);
        controller.dispose();
      });

      test('rejects password shorter than 8 characters', () async {
        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(username: 'user', password: 'short');

        expect(controller.state, RegistrationState.formReady);
        expect(controller.passwordError, contains('8 characters'));
        controller.dispose();
      });

      test('sets usernameError when username is taken', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_USER_IN_USE',
            'error': 'Desired user ID is already taken.',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'takenuser', password: 'password123');

        expect(controller.state, RegistrationState.formReady);
        expect(controller.usernameError, contains('already taken'));
        controller.dispose();
      });

      test('sets usernameError when username is invalid', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_INVALID_USERNAME',
            'error': 'User ID contains invalid characters.',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'bad@user', password: 'password123');

        expect(controller.state, RegistrationState.formReady);
        expect(controller.usernameError, contains('invalid'));
        controller.dispose();
      });

      test('transitions to done on successful registration with dummy stage',
          () async {
        // First register call returns 401 with dummy flow
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.dummy'],
              },
            ],
            'session': 'sess1',
          }),
        );

        final controller = createController();
        await controller.checkServer();

        // Now mock the second register call (with dummy auth) to succeed
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenAnswer((_) async => RegisterResponse(
              userId: '@newuser:example.com',
              accessToken: 'token',
              deviceId: 'DEV1',
            ));
        when(mockMatrixService.completeRegistration(any))
            .thenAnswer((_) async {});

        await controller.submitForm(
            username: 'newuser', password: 'goodpass1');

        expect(controller.state, RegistrationState.done);
        controller.dispose();
      });

      test('sets error on M_FORBIDDEN', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_FORBIDDEN',
            'error': 'Registration is not allowed on this server',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.error);
        expect(controller.error, contains('not allowed'));
        controller.dispose();
      });

      test('transitions to enterEmail when email stage is required', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.email.identity'],
              },
            ],
            'session': 'sess2',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.enterEmail);
        controller.dispose();
      });

      test('transitions to recaptcha when recaptcha stage is required',
          () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.recaptcha'],
              },
            ],
            'session': 'sess3',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.recaptcha);
        controller.dispose();
      });

      test('transitions to acceptTerms when terms stage is required', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.terms'],
              },
            ],
            'session': 'sess4',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.acceptTerms);
        controller.dispose();
      });

      test('sets error for unsupported UIA stage', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.unknown_stage'],
              },
            ],
            'session': 'sess5',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.error);
        expect(controller.error, contains('Unsupported'));
        controller.dispose();
      });

      test('calls completeRegistration on success', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenAnswer((_) async => RegisterResponse(
              userId: '@user:example.com',
              accessToken: 'tok',
              deviceId: 'D1',
            ));
        when(mockMatrixService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        verify(mockMatrixService.completeRegistration(
          any,
          password: anyNamed('password'),
        )).called(1);
        controller.dispose();
      });

      test('passes password to completeRegistration', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenAnswer((_) async => RegisterResponse(
              userId: '@user:example.com',
              accessToken: 'tok',
              deviceId: 'D1',
            ));
        when(mockMatrixService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'mypassword123');

        final captured = verify(mockMatrixService.completeRegistration(
          any,
          password: captureAnyNamed('password'),
        )).captured;
        expect(captured.single, 'mypassword123');
        controller.dispose();
      });

      test('guards against concurrent submit calls', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenAnswer((_) async => RegisterResponse(
              userId: '@user:example.com',
              accessToken: 'tok',
              deviceId: 'D1',
            ));
        when(mockMatrixService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();

        // Fire two submits — second should be blocked by guard.
        final f1 = controller.submitForm(
            username: 'user', password: 'password123');
        final f2 = controller.submitForm(
            username: 'user', password: 'password123');
        await f1;
        await f2;

        // register should only be called once.
        verify(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).called(1);
        controller.dispose();
      });

      test('shows friendly message for SocketException', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(const SocketException('Connection refused'));

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.error);
        expect(controller.error, 'Could not reach server');
        controller.dispose();
      });

      test('shows friendly message for TimeoutException', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(TimeoutException('timed out'));

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.error);
        expect(controller.error, 'Connection timed out');
        controller.dispose();
      });
    });

    group('cancelRegistration', () {
      setUp(() {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ));
      });

      test('resets from UIA stage to formReady', () async {
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenThrow(
          MatrixException.fromJson({
            'flows': [
              {
                'stages': ['m.login.email.identity'],
              },
            ],
            'session': 'sess1',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.enterEmail);

        controller.cancelRegistration();

        expect(controller.state, RegistrationState.formReady);
        expect(controller.error, isNull);
        controller.dispose();
      });
    });

    group('dispose', () {
      test('does not notify after dispose', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                ));

        final controller = createController();
        await controller.checkServer();

        var notifiedAfterDispose = false;
        controller.addListener(() => notifiedAfterDispose = true);
        controller.dispose();

        // Calling checkServer after dispose should not throw or notify.
        await controller.checkServer();
        expect(notifiedAfterDispose, isFalse);
      });
    });
  });
}

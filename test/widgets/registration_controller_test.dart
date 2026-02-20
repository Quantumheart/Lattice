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

    group('requiresToken', () {
      test('returns true when registration stages include registration_token',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.registration_token'],
                ));

        final controller = createController();
        await controller.checkServer();

        expect(controller.requiresToken, isTrue);
        controller.dispose();
      });

      test('returns false when registration stages do not include token',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ));

        final controller = createController();
        await controller.checkServer();

        expect(controller.requiresToken, isFalse);
        controller.dispose();
      });

      test('rejects empty token when requiresToken is true', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.registration_token'],
                ));

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123', token: '');

        expect(controller.tokenError, isNotNull);
        expect(controller.state, RegistrationState.formReady);
        controller.dispose();
      });

      test('auto-completes registration_token UIA stage with provided token',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.registration_token'],
                ));

        final controller = createController();
        await controller.checkServer();

        when(mockMatrixService.completeRegistration(any))
            .thenAnswer((_) async {});

        // First call throws UIA challenge, second call succeeds.
        var callCount = 0;
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenAnswer((invocation) {
          callCount++;
          if (callCount == 1) {
            throw MatrixException.fromJson({
              'flows': [
                {
                  'stages': ['m.login.registration_token'],
                },
              ],
              'session': 'token_sess',
            });
          }
          return Future.value(RegisterResponse(
            userId: '@user:example.com',
            accessToken: 'tok',
            deviceId: 'D1',
          ));
        });

        await controller.submitForm(
            username: 'user', password: 'password123', token: 'mytoken');

        // _advanceToNextStage fires _attemptRegister without await,
        // so pump the event loop to let the recursive call complete.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.state, RegistrationState.done);

        // Verify register was called with auth containing the token.
        final captured = verify(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: captureAnyNamed('auth'),
        )).captured;
        // Find the non-null auth argument (second call with token auth).
        final tokenAuth = captured.whereType<AuthenticationData>().last;
        final json = tokenAuth.toJson();
        expect(json['type'], 'm.login.registration_token');
        expect(json['token'], 'mytoken');
        controller.dispose();
      });
    });

    group('UIA params', () {
      setUp(() {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ));
      });

      test('extracts recaptchaPublicKey from UIA params', () async {
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
            'session': 'sess_captcha',
            'params': {
              'm.login.recaptcha': {'public_key': 'test_site_key_123'},
            },
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.recaptcha);
        expect(controller.recaptchaPublicKey, 'test_site_key_123');
        controller.dispose();
      });

      test('recaptchaPublicKey is null when no params', () async {
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
            'session': 'sess_captcha',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.recaptcha);
        expect(controller.recaptchaPublicKey, isNull);
        controller.dispose();
      });

      test('extracts termsOfServicePolicies from UIA params', () async {
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
            'session': 'sess_terms',
            'params': {
              'm.login.terms': {
                'policies': {
                  'privacy_policy': {
                    'version': '1.0',
                    'en': {
                      'name': 'Privacy Policy',
                      'url': 'https://example.com/privacy',
                    },
                  },
                  'tos': {
                    'version': '2.0',
                    'en': {
                      'name': 'Terms of Service',
                      'url': 'https://example.com/tos',
                    },
                  },
                },
              },
            },
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.acceptTerms);
        final policies = controller.termsOfServicePolicies;
        expect(policies, hasLength(2));
        expect(policies.any((p) => p.name == 'Privacy Policy'), isTrue);
        expect(policies.any((p) => p.name == 'Terms of Service'), isTrue);
        controller.dispose();
      });

      test('termsOfServicePolicies is empty when no params', () async {
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
            'session': 'sess_terms',
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.termsOfServicePolicies, isEmpty);
        controller.dispose();
      });
    });

    group('submitTerms', () {
      setUp(() {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ));
      });

      test('submits m.login.terms auth and advances', () async {
        var callCount = 0;
        when(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: anyNamed('auth'),
        )).thenAnswer((invocation) {
          callCount++;
          if (callCount == 1) {
            throw MatrixException.fromJson({
              'flows': [
                {
                  'stages': ['m.login.terms'],
                },
              ],
              'session': 'sess_terms',
              'params': {
                'm.login.terms': {
                  'policies': {
                    'tos': {
                      'version': '1.0',
                      'en': {
                        'name': 'Terms',
                        'url': 'https://example.com/tos',
                      },
                    },
                  },
                },
              },
            });
          }
          return Future.value(RegisterResponse(
            userId: '@user:example.com',
            accessToken: 'tok',
            deviceId: 'D1',
          ));
        });
        when(mockMatrixService.completeRegistration(any))
            .thenAnswer((_) async {});

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.acceptTerms);

        await controller.submitTerms();
        await Future<void>.delayed(Duration.zero);

        expect(controller.state, RegistrationState.done);

        final captured = verify(mockClient.register(
          username: anyNamed('username'),
          password: anyNamed('password'),
          initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
          auth: captureAnyNamed('auth'),
        )).captured;
        final termsAuth = captured.whereType<AuthenticationData>().last;
        expect(termsAuth.toJson()['type'], 'm.login.terms');
        controller.dispose();
      });

      test('ignores submitTerms when not in acceptTerms state', () async {
        final controller = createController();
        await controller.checkServer();

        // Should be a no-op.
        await controller.submitTerms();
        expect(controller.state, RegistrationState.formReady);
        controller.dispose();
      });
    });

    group('cancelRegistration clears UIA state', () {
      setUp(() {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsRegistration: true,
                  registrationStages: ['m.login.dummy'],
                ));
      });

      test('clears uiaParams and recaptcha state on cancel', () async {
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
            'session': 'sess_captcha',
            'params': {
              'm.login.recaptcha': {'public_key': 'key123'},
            },
          }),
        );

        final controller = createController();
        await controller.checkServer();
        await controller.submitForm(
            username: 'user', password: 'password123');

        expect(controller.state, RegistrationState.recaptcha);
        expect(controller.recaptchaPublicKey, 'key123');

        controller.cancelRegistration();

        expect(controller.state, RegistrationState.formReady);
        expect(controller.recaptchaPublicKey, isNull);
        expect(controller.recaptchaWaiting, isFalse);
        controller.dispose();
      });
    });

    group('submitForm state guard', () {
      test('ignores submit when not in formReady state', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenThrow(Exception('Connection refused'));

        final controller = createController();
        await controller.checkServer();
        expect(controller.state, RegistrationState.error);

        // Submit should be a no-op in error state.
        await controller.submitForm(
            username: 'user', password: 'password123');
        expect(controller.state, RegistrationState.error);
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

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:lattice/services/matrix_service.dart';

import 'matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    service = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
  });

  group('getServerAuthCapabilities', () {
    setUp(() {
      when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
            null,
            GetVersionsResponse.fromJson({'versions': ['v1.1']}),
            <LoginFlow>[],
            null,
          ));
    });

    test('returns supportsPassword true when m.login.password flow exists',
        () async {
      when(mockClient.getLoginFlows()).thenAnswer((_) async => [
            LoginFlow(type: AuthenticationTypes.password),
          ]);
      // Registration probe returns 403 (disabled)
      when(mockClient.request(RequestType.POST, '/client/v3/register',
              data: anyNamed('data')))
          .thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Registration is not enabled',
        }),
      );

      final caps = await service.getServerAuthCapabilities('example.com');

      expect(caps.supportsPassword, isTrue);
      expect(caps.supportsSso, isFalse);
    });

    test('returns supportsSso true when m.login.sso flow exists', () async {
      when(mockClient.getLoginFlows()).thenAnswer((_) async => [
            LoginFlow(type: AuthenticationTypes.sso),
          ]);
      when(mockClient.request(RequestType.POST, '/client/v3/register',
              data: anyNamed('data')))
          .thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Registration is not enabled',
        }),
      );

      final caps = await service.getServerAuthCapabilities('example.com');

      expect(caps.supportsSso, isTrue);
    });

    test('extracts SSO identity providers from login flow', () async {
      when(mockClient.getLoginFlows()).thenAnswer((_) async => [
            LoginFlow(
              type: AuthenticationTypes.sso,
              additionalProperties: {
                'identity_providers': [
                  {'id': 'google', 'name': 'Google'},
                  {'id': 'github', 'name': 'GitHub'},
                ],
              },
            ),
          ]);
      when(mockClient.request(RequestType.POST, '/client/v3/register',
              data: anyNamed('data')))
          .thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Registration is not enabled',
        }),
      );

      final caps = await service.getServerAuthCapabilities('example.com');

      expect(caps.ssoIdentityProviders, hasLength(2));
      expect(caps.ssoIdentityProviders[0].id, 'google');
      expect(caps.ssoIdentityProviders[0].name, 'Google');
      expect(caps.ssoIdentityProviders[1].id, 'github');
      expect(caps.ssoIdentityProviders[1].name, 'GitHub');
    });

    test(
        'returns supportsRegistration true when register probe returns 401 with flows',
        () async {
      when(mockClient.getLoginFlows()).thenAnswer((_) async => [
            LoginFlow(type: AuthenticationTypes.password),
          ]);
      when(mockClient.request(RequestType.POST, '/client/v3/register',
              data: anyNamed('data')))
          .thenThrow(
        MatrixException.fromJson({
          'flows': [
            {
              'stages': ['m.login.dummy'],
            },
          ],
          'session': 'test_session',
        }),
      );

      final caps = await service.getServerAuthCapabilities('example.com');

      expect(caps.supportsRegistration, isTrue);
      expect(caps.registrationStages, contains('m.login.dummy'));
    });

    test(
        'returns supportsRegistration false when register probe returns M_FORBIDDEN',
        () async {
      when(mockClient.getLoginFlows()).thenAnswer((_) async => [
            LoginFlow(type: AuthenticationTypes.password),
          ]);
      when(mockClient.request(RequestType.POST, '/client/v3/register',
              data: anyNamed('data')))
          .thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Registration is not enabled on this homeserver',
        }),
      );

      final caps = await service.getServerAuthCapabilities('example.com');

      expect(caps.supportsRegistration, isFalse);
    });

    test('handles network errors gracefully', () async {
      when(mockClient.checkHomeserver(any))
          .thenThrow(Exception('Connection refused'));

      expect(
        () => service.getServerAuthCapabilities('bad.server'),
        throwsA(isA<Exception>()),
      );
    });

    test('throws ArgumentError for empty homeserver', () async {
      expect(
        () => service.getServerAuthCapabilities(''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => service.getServerAuthCapabilities('   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('auto-prefixes https if missing', () async {
      when(mockClient.getLoginFlows()).thenAnswer((_) async => []);
      when(mockClient.request(RequestType.POST, '/client/v3/register',
              data: anyNamed('data')))
          .thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Registration is not enabled',
        }),
      );

      await service.getServerAuthCapabilities('example.com');

      verify(mockClient.checkHomeserver(
        Uri.parse('https://example.com'),
      )).called(1);
    });

    test('returns all capabilities when server supports everything', () async {
      when(mockClient.getLoginFlows()).thenAnswer((_) async => [
            LoginFlow(type: AuthenticationTypes.password),
            LoginFlow(
              type: AuthenticationTypes.sso,
              additionalProperties: {
                'identity_providers': [
                  {'id': 'oidc', 'name': 'OIDC Provider'},
                ],
              },
            ),
          ]);
      when(mockClient.request(RequestType.POST, '/client/v3/register',
              data: anyNamed('data')))
          .thenThrow(
        MatrixException.fromJson({
          'flows': [
            {
              'stages': [
                'm.login.recaptcha',
                'm.login.terms',
                'm.login.dummy',
              ],
            },
          ],
          'session': 'sess123',
        }),
      );

      final caps = await service.getServerAuthCapabilities('example.com');

      expect(caps.supportsPassword, isTrue);
      expect(caps.supportsSso, isTrue);
      expect(caps.supportsRegistration, isTrue);
      expect(caps.ssoIdentityProviders, hasLength(1));
      expect(caps.ssoIdentityProviders[0].id, 'oidc');
      expect(caps.ssoIdentityProviders[0].name, 'OIDC Provider');
      expect(caps.registrationStages, hasLength(3));
    });

    test('returns empty capabilities when called while logged in', () async {
      service.isLoggedInForTest = true;

      final caps = await service.getServerAuthCapabilities('example.com');

      expect(caps.supportsPassword, isFalse);
      expect(caps.supportsSso, isFalse);
      expect(caps.supportsRegistration, isFalse);
      verifyNever(mockClient.checkHomeserver(any));
    });

    test('handles null getLoginFlows response', () async {
      when(mockClient.getLoginFlows()).thenAnswer((_) async => null);
      when(mockClient.request(RequestType.POST, '/client/v3/register',
              data: anyNamed('data')))
          .thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Registration is not enabled',
        }),
      );

      final caps = await service.getServerAuthCapabilities('example.com');

      expect(caps.supportsPassword, isFalse);
      expect(caps.supportsSso, isFalse);
    });
  });

  group('completeSsoLogin', () {
    late CachedStreamController<SyncUpdate> syncController;

    setUp(() {
      syncController = CachedStreamController<SyncUpdate>();
      when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
            null,
            GetVersionsResponse.fromJson({'versions': ['v1.1']}),
            <LoginFlow>[],
            null,
          ));
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
      when(mockClient.onLoginStateChanged)
          .thenReturn(CachedStreamController());
    });

    test('logs in with mLoginToken and persists credentials', () async {
      when(mockClient.login(
        any,
        token: anyNamed('token'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).thenAnswer((_) async => LoginResponse.fromJson({
            'access_token': 'sso_token',
            'device_id': 'SSO_DEV',
            'user_id': '@ssouser:example.com',
          }));
      when(mockClient.accessToken).thenReturn('sso_token');
      when(mockClient.userID).thenReturn('@ssouser:example.com');
      when(mockClient.homeserver)
          .thenReturn(Uri.parse('https://example.com'));
      when(mockClient.deviceID).thenReturn('SSO_DEV');
      when(mockClient.encryption).thenReturn(null);

      Future.delayed(
          Duration.zero, () => syncController.add(SyncUpdate(nextBatch: 'b1')));

      final result = await service.completeSsoLogin(
        homeserver: 'example.com',
        loginToken: 'test_sso_token',
      );

      expect(result, isTrue);
      expect(service.isLoggedIn, isTrue);

      // Verify login was called with mLoginToken
      verify(mockClient.login(
        LoginType.mLoginToken,
        token: 'test_sso_token',
        initialDeviceDisplayName: 'Lattice Flutter',
      )).called(1);

      // Verify credentials persisted
      verify(mockStorage.write(
              key: 'lattice_test_access_token', value: 'sso_token'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_test_user_id', value: '@ssouser:example.com'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_test_homeserver', value: 'https://example.com'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_test_device_id', value: 'SSO_DEV'))
          .called(1);
    });

    test('sets loginError on failure and returns false', () async {
      when(mockClient.login(
        any,
        token: anyNamed('token'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).thenThrow(Exception('Invalid login token'));

      final result = await service.completeSsoLogin(
        homeserver: 'example.com',
        loginToken: 'bad_token',
      );

      expect(result, isFalse);
      expect(service.isLoggedIn, isFalse);
      expect(service.loginError, contains('Invalid login token'));
    });

    test('clears previous loginError before attempting', () async {
      // First cause an error
      when(mockClient.login(
        any,
        token: anyNamed('token'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).thenThrow(Exception('first error'));
      await service.completeSsoLogin(
        homeserver: 'example.com',
        loginToken: 'bad',
      );
      expect(service.loginError, isNotNull);

      // Now succeed
      when(mockClient.login(
        any,
        token: anyNamed('token'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).thenAnswer((_) async => LoginResponse.fromJson({
            'access_token': 'tok',
            'device_id': 'D1',
            'user_id': '@u:e.com',
          }));
      when(mockClient.accessToken).thenReturn('tok');
      when(mockClient.userID).thenReturn('@u:e.com');
      when(mockClient.homeserver).thenReturn(Uri.parse('https://e.com'));
      when(mockClient.deviceID).thenReturn('D1');
      when(mockClient.encryption).thenReturn(null);

      Future.delayed(
          Duration.zero, () => syncController.add(SyncUpdate(nextBatch: 'b')));

      final result = await service.completeSsoLogin(
        homeserver: 'example.com',
        loginToken: 'good',
      );

      expect(result, isTrue);
      expect(service.loginError, isNull);
    });
  });

  group('completeRegistration', () {
    late CachedStreamController<SyncUpdate> syncController;

    setUp(() {
      syncController = CachedStreamController<SyncUpdate>();
      when(mockClient.accessToken).thenReturn('reg_token');
      when(mockClient.userID).thenReturn('@newuser:example.com');
      when(mockClient.homeserver)
          .thenReturn(Uri.parse('https://example.com'));
      when(mockClient.deviceID).thenReturn('REG_DEV');
      when(mockClient.encryption).thenReturn(null);
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
      when(mockClient.onLoginStateChanged)
          .thenReturn(CachedStreamController());
    });

    test('persists credentials and sets isLoggedIn', () async {
      Future.delayed(Duration.zero,
          () => syncController.add(SyncUpdate(nextBatch: 'b1')));

      await service.completeRegistration(RegisterResponse(
        userId: '@newuser:example.com',
        accessToken: 'reg_token',
        deviceId: 'REG_DEV',
      ));

      expect(service.isLoggedIn, isTrue);
      verify(mockStorage.write(
              key: 'lattice_test_access_token', value: 'reg_token'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_test_user_id', value: '@newuser:example.com'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_test_homeserver', value: 'https://example.com'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_test_device_id', value: 'REG_DEV'))
          .called(1);
    });

    test('saves session backup', () async {
      Future.delayed(Duration.zero,
          () => syncController.add(SyncUpdate(nextBatch: 'b1')));

      await service.completeRegistration(RegisterResponse(
        userId: '@newuser:example.com',
        accessToken: 'reg_token',
        deviceId: 'REG_DEV',
      ));

      // Let background sync + session backup complete.
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      verify(mockStorage.write(
        key: 'lattice_session_backup_test',
        value: anyNamed('value'),
      )).called(1);
    });

    test('notifies listeners', () async {
      Future.delayed(Duration.zero,
          () => syncController.add(SyncUpdate(nextBatch: 'b1')));

      var notified = false;
      service.addListener(() => notified = true);

      await service.completeRegistration(RegisterResponse(
        userId: '@newuser:example.com',
        accessToken: 'reg_token',
        deviceId: 'REG_DEV',
      ));

      expect(notified, isTrue);
    });

    test('throws StateError when client is not initialized', () async {
      when(mockClient.accessToken).thenReturn(null);
      when(mockClient.userID).thenReturn(null);

      expect(
        () => service.completeRegistration(RegisterResponse(
          userId: '@newuser:example.com',
          accessToken: 'reg_token',
          deviceId: 'REG_DEV',
        )),
        throwsA(isA<StateError>()),
      );
    });
  });
}

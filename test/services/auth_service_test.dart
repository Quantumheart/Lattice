import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/sub_services/auth_service.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

class _FakeDatabase extends Fake implements DatabaseApi {
  @override
  Future<Map<String, dynamic>?> getClient(String name) async => null;
}

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late AuthService service;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.database).thenReturn(_FakeDatabase());
    service = AuthService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
  });

  group('getServerAuthCapabilities', () {
    setUp(() {
      when(mockClient.checkHomeserver(any)).thenAnswer(
        (_) async => (
          null,
          GetVersionsResponse.fromJson({'versions': ['v1.1']}),
          <LoginFlow>[],
          null,
        ),
      );
    });

    test('probes login flows and registration', () async {
      when(mockClient.getLoginFlows()).thenAnswer(
        (_) async => [
          LoginFlow(type: AuthenticationTypes.password),
        ],
      );
      when(
        mockClient.request(
          RequestType.POST,
          '/client/v3/register',
          data: anyNamed('data'),
        ),
      ).thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Registration disabled',
        }),
      );

      final caps = await service.getServerAuthCapabilities(
        'example.com',
        isLoggedIn: false,
      );

      expect(caps.supportsPassword, isTrue);
      expect(caps.supportsSso, isFalse);
      expect(caps.supportsRegistration, isFalse);
    });

    test('skips when logged in', () async {
      final caps = await service.getServerAuthCapabilities(
        'example.com',
        isLoggedIn: true,
      );

      expect(caps.supportsPassword, isFalse);
      verifyNever(mockClient.checkHomeserver(any));
    });

    test('throws ArgumentError for empty homeserver', () async {
      expect(
        () => service.getServerAuthCapabilities('', isLoggedIn: false),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('serializes concurrent probes', () async {
      when(mockClient.getLoginFlows()).thenAnswer((_) async => []);
      when(
        mockClient.request(
          RequestType.POST,
          '/client/v3/register',
          data: anyNamed('data'),
        ),
      ).thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Registration disabled',
        }),
      );

      final futures = [
        service.getServerAuthCapabilities(
          'example.com',
          isLoggedIn: false,
        ),
        service.getServerAuthCapabilities(
          'other.com',
          isLoggedIn: false,
        ),
      ];

      await Future.wait(futures);

      verify(mockClient.checkHomeserver(any)).called(2);
    });
  });

  group('isPermanentAuthFailure', () {
    test('classifies M_UNKNOWN_TOKEN as permanent', () {
      final error = MatrixException.fromJson({
        'errcode': 'M_UNKNOWN_TOKEN',
        'error': 'Token revoked',
      });

      expect(service.isPermanentAuthFailure(error), isTrue);
    });

    test('classifies M_FORBIDDEN as permanent', () {
      final error = MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Forbidden',
      });

      expect(service.isPermanentAuthFailure(error), isTrue);
    });

    test('classifies M_USER_DEACTIVATED as permanent', () {
      final error = MatrixException.fromJson({
        'errcode': 'M_USER_DEACTIVATED',
        'error': 'User deactivated',
      });

      expect(service.isPermanentAuthFailure(error), isTrue);
    });

    test('classifies network errors as non-permanent', () {
      expect(
        service.isPermanentAuthFailure(Exception('network')),
        isFalse,
      );
    });
  });

  group('clearSessionKeys', () {
    test('deletes all 6 storage keys', () async {
      await service.clearSessionKeys();

      verify(
        mockStorage.delete(key: 'lattice_test_access_token'),
      ).called(1);
      verify(
        mockStorage.delete(key: 'lattice_test_refresh_token'),
      ).called(1);
      verify(
        mockStorage.delete(key: 'lattice_test_user_id'),
      ).called(1);
      verify(
        mockStorage.delete(key: 'lattice_test_homeserver'),
      ).called(1);
      verify(
        mockStorage.delete(key: 'lattice_test_device_id'),
      ).called(1);
      verify(
        mockStorage.delete(key: 'lattice_test_olm_account'),
      ).called(1);
    });
  });

  group('migrateStorageKeys', () {
    test('migrates old keys for default client', () async {
      final defaultService = AuthService(
        client: mockClient,
        storage: mockStorage,
        clientName: 'default',
        );

      when(mockStorage.read(key: 'lattice_access_token'))
          .thenAnswer((_) async => 'old_token');
      when(mockStorage.read(key: 'lattice_user_id'))
          .thenAnswer((_) async => '@user:e.com');
      when(mockStorage.read(key: 'lattice_homeserver'))
          .thenAnswer((_) async => 'https://e.com');
      when(mockStorage.read(key: 'lattice_device_id'))
          .thenAnswer((_) async => 'D1');
      when(mockStorage.read(key: 'lattice_olm_account'))
          .thenAnswer((_) async => null);

      await defaultService.migrateStorageKeys();

      verify(
        mockStorage.write(
          key: 'lattice_default_access_token',
          value: 'old_token',
        ),
      ).called(1);
    });

    test('is no-op for non-default client', () async {
      await service.migrateStorageKeys();

      verifyNever(mockStorage.read(key: 'lattice_access_token'));
    });
  });

  group('persistCredentials', () {
    test('writes all 5 storage keys', () async {
      when(mockClient.accessToken).thenReturn('token');
      when(mockClient.userID).thenReturn('@user:e.com');
      when(mockClient.homeserver).thenReturn(Uri.parse('https://e.com'));
      when(mockClient.deviceID).thenReturn('D1');

      await service.persistCredentials();

      verify(
        mockStorage.write(
          key: 'lattice_test_access_token',
          value: 'token',
        ),
      ).called(1);
      verify(
        mockStorage.write(
          key: 'lattice_test_refresh_token',
          value: null,
        ),
      ).called(1);
      verify(
        mockStorage.write(
          key: 'lattice_test_user_id',
          value: '@user:e.com',
        ),
      ).called(1);
      verify(
        mockStorage.write(
          key: 'lattice_test_homeserver',
          value: 'https://e.com',
        ),
      ).called(1);
      verify(
        mockStorage.write(
          key: 'lattice_test_device_id',
          value: 'D1',
        ),
      ).called(1);
    });
  });

  group('loginError', () {
    test('getter and setter work', () {
      expect(service.loginError, isNull);
      service.loginError = 'bad';
      expect(service.loginError, 'bad');
    });
  });
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<SharedPreferences>(),
])
import 'client_manager_test.mocks.dart';
import 'matrix_service_test.mocks.dart';

/// Test implementation of [MatrixServiceFactory] that creates services with
/// injected mock clients.
class _TestServiceFactory extends MatrixServiceFactory {
  _TestServiceFactory({
    this.trackNames,
    this.trackServices,
  });

  final List<String>? trackNames;
  final List<MatrixService>? trackServices;

  @override
  Future<(Client, MatrixService)> create({
    required String clientName,
    FlutterSecureStorage? storage,
  }) async {
    trackNames?.add(clientName);
    final mockClient = MockClient();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.userID).thenReturn('@$clientName:example.com');
    when(mockClient.dispose()).thenAnswer((_) async {});
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    final s = MatrixService(
      client: mockClient,
      storage: storage ?? const FlutterSecureStorage(),
      clientName: clientName,
    );
    s.isLoggedInForTest = true;
    trackServices?.add(s);
    return (mockClient, s);
  }
}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late MockSharedPreferences mockPrefs;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    mockPrefs = MockSharedPreferences();
  });

  group('init', () {
    test('creates single default service when no stored names', () async {
      when(mockPrefs.getStringList('kohera_client_names')).thenReturn(null);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final createdNames = <String>[];
      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _TestServiceFactory(trackNames: createdNames),
      );

      await manager.init();

      expect(createdNames, ['default']);
      expect(manager.services, hasLength(1));
      expect(manager.activeIndex, 0);
    });

    test('creates services for each stored name', () async {
      when(mockPrefs.getStringList('kohera_client_names'))
          .thenReturn(['default', 'work']);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final createdNames = <String>[];
      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _TestServiceFactory(trackNames: createdNames),
      );

      await manager.init();

      expect(createdNames, ['default', 'work']);
      expect(manager.services, hasLength(2));
    });

    test('removes non-logged-in services in multi-account init', () async {
      when(mockPrefs.getStringList('kohera_client_names'))
          .thenReturn(['default', 'expired']);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _MixedLoginFactory(mockStorage),
      );

      await manager.init();

      // 'expired' was removed because it's not logged in.
      expect(manager.services, hasLength(1));
      expect(manager.activeService.clientName, 'default');
    });
  });

  group('setActiveAccount', () {
    test('switches active service and notifies listeners', () async {
      when(mockPrefs.getStringList('kohera_client_names'))
          .thenReturn(['default', 'work']);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _TestServiceFactory(),
      );
      await manager.init();

      var notified = false;
      manager.addListener(() => notified = true);

      manager.setActiveAccount(1);

      expect(manager.activeIndex, 1);
      expect(manager.activeService.clientName, 'work');
      expect(notified, isTrue);
    });

    test('ignores out-of-bounds index', () async {
      when(mockPrefs.getStringList('kohera_client_names')).thenReturn(null);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _TestServiceFactory(),
      );
      await manager.init();

      manager.setActiveAccount(5);

      expect(manager.activeIndex, 0);
    });
  });

  group('addService', () {
    test('adds service, makes it active, and persists names', () async {
      when(mockPrefs.getStringList('kohera_client_names')).thenReturn(null);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _TestServiceFactory(),
      );
      await manager.init();

      final newMockClient = MockClient();
      when(newMockClient.rooms).thenReturn([]);
      when(newMockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
      final newService = MatrixService(
        client: newMockClient,
        storage: mockStorage,
        clientName: 'account_1',
      );

      await manager.addService(newService);

      expect(manager.services, hasLength(2));
      expect(manager.activeIndex, 1);
      expect(manager.activeService.clientName, 'account_1');
      verify(mockPrefs.setStringList(
        'kohera_client_names',
        ['default', 'account_1'],
      ),).called(1);
    });
  });

  group('removeService', () {
    test('removes service and adjusts active index', () async {
      when(mockPrefs.getStringList('kohera_client_names'))
          .thenReturn(['default', 'work']);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final services = <MatrixService>[];
      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _TestServiceFactory(trackServices: services),
      );
      await manager.init();

      manager.setActiveAccount(1);
      expect(manager.activeService.clientName, 'work');

      await manager.removeService(services[0]);

      expect(manager.services, hasLength(1));
      expect(manager.activeIndex, 0);
      expect(manager.activeService.clientName, 'work');
    });

    test('creates fresh default when last account removed', () async {
      when(mockPrefs.getStringList('kohera_client_names')).thenReturn(null);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final services = <MatrixService>[];
      var callCount = 0;
      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _CountingFactory(
          mockStorage,
          trackServices: services,
          callCounter: () => callCount++,
        ),
      );
      await manager.init();

      await manager.removeService(services[0]);

      expect(manager.services, hasLength(1));
      expect(manager.activeService.clientName, 'default');
      // A new service was created (factory called twice total).
      expect(callCount, 2);
    });
  });

  group('signOut', () {
    test(
      'switches active before logging out when other accounts exist',
      () async {
        when(mockPrefs.getStringList('kohera_client_names'))
            .thenReturn(['default', 'work']);
        when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);
        when(mockStorage.delete(key: anyNamed('key')))
            .thenAnswer((_) async {});

        final services = <MatrixService>[];
        final manager = ClientManager(
          storage: mockStorage,
          prefs: mockPrefs,
          serviceFactory: _TestServiceFactory(trackServices: services),
        );
        await manager.init();

        // Active is services[0] ('default'). Sign out of it.
        final target = services[0];

        // Record manager notifications: each time ClientManager notifies,
        // capture the currently active service's logged-in state.
        final activeLoggedSnapshots = <bool>[];
        manager.addListener(() {
          activeLoggedSnapshots
              .add(manager.activeService.isLoggedIn);
        });

        await manager.signOut(target);

        // Regression: active must switch *before* logout, so every
        // notification during sign-out observes a logged-in active.
        expect(activeLoggedSnapshots, isNotEmpty);
        expect(activeLoggedSnapshots, everyElement(isTrue));

        expect(manager.services, hasLength(1));
        expect(manager.activeService.clientName, 'work');
      },
    );

    test('falls through to login flow when last account signs out',
        () async {
      when(mockPrefs.getStringList('kohera_client_names')).thenReturn(null);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);
      when(mockStorage.delete(key: anyNamed('key')))
          .thenAnswer((_) async {});

      final services = <MatrixService>[];
      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _TestServiceFactory(trackServices: services),
      );
      await manager.init();

      await manager.signOut(services[0]);

      // Fresh default was created; it's not logged in (fresh client).
      expect(manager.services, hasLength(1));
    });
  });

  group('hasMultipleAccounts', () {
    test('returns false with single account', () async {
      when(mockPrefs.getStringList('kohera_client_names')).thenReturn(null);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _TestServiceFactory(),
      );
      await manager.init();

      expect(manager.hasMultipleAccounts, isFalse);
    });

    test('returns true with multiple accounts', () async {
      when(mockPrefs.getStringList('kohera_client_names'))
          .thenReturn(['default', 'work']);
      when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);

      final manager = ClientManager(
        storage: mockStorage,
        prefs: mockPrefs,
        serviceFactory: _TestServiceFactory(),
      );
      await manager.init();

      expect(manager.hasMultipleAccounts, isTrue);
    });
  });
}

/// Factory that only marks 'default' as logged in.
class _MixedLoginFactory extends MatrixServiceFactory {
  _MixedLoginFactory(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<(Client, MatrixService)> create({
    required String clientName,
    FlutterSecureStorage? storage,
  }) async {
    final mockClient = MockClient();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.userID).thenReturn('@$clientName:example.com');
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    final s = MatrixService(
      client: mockClient,
      storage: storage ?? _storage,
      clientName: clientName,
    );
    // Only the first service is logged in.
    if (clientName == 'default') s.isLoggedInForTest = true;
    return (mockClient, s);
  }
}

/// Factory that counts calls and tracks services.
class _CountingFactory extends MatrixServiceFactory {
  _CountingFactory(
    this._storage, {
    this.trackServices,
    this.callCounter,
  });

  final FlutterSecureStorage _storage;
  final List<MatrixService>? trackServices;
  final void Function()? callCounter;

  @override
  Future<(Client, MatrixService)> create({
    required String clientName,
    FlutterSecureStorage? storage,
  }) async {
    callCounter?.call();
    final mockClient = MockClient();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.dispose()).thenAnswer((_) async {});
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    final s = MatrixService(
      client: mockClient,
      storage: storage ?? _storage,
      clientName: clientName,
    );
    s.isLoggedInForTest = true;
    trackServices?.add(s);
    return (mockClient, s);
  }
}

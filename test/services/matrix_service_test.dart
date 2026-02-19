import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/cross_signing.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lattice/services/matrix_service.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<FlutterSecureStorage>(),
  MockSpec<Encryption>(),
  MockSpec<CrossSigning>(),
  MockSpec<KeyManager>(),
  MockSpec<Bootstrap>(),
  MockSpec<OpenSSSS>(),
])
import 'matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    service = MatrixService(client: mockClient, storage: mockStorage);
  });

  group('selectSpace', () {
    test('updates selectedSpaceId and notifies listeners', () {
      var notified = false;
      service.addListener(() => notified = true);

      service.selectSpace('!space:example.com');

      expect(service.selectedSpaceId, '!space:example.com');
      expect(notified, isTrue);
    });

    test('can be cleared to null', () {
      service.selectSpace('!space:example.com');
      service.selectSpace(null);

      expect(service.selectedSpaceId, isNull);
    });
  });

  group('selectRoom', () {
    test('updates selectedRoomId and notifies listeners', () {
      var notified = false;
      service.addListener(() => notified = true);

      service.selectRoom('!room:example.com');

      expect(service.selectedRoomId, '!room:example.com');
      expect(notified, isTrue);
    });

    test('can be cleared to null', () {
      service.selectRoom('!room:example.com');
      service.selectRoom(null);

      expect(service.selectedRoomId, isNull);
    });
  });

  group('spaces getter', () {
    test('filters rooms to only spaces and sorts alphabetically', () {
      final space1 = MockRoom();
      when(space1.isSpace).thenReturn(true);
      when(space1.getLocalizedDisplayname()).thenReturn('B Space');

      final space2 = MockRoom();
      when(space2.isSpace).thenReturn(true);
      when(space2.getLocalizedDisplayname()).thenReturn('A Space');

      final room1 = MockRoom();
      when(room1.isSpace).thenReturn(false);

      when(mockClient.rooms).thenReturn([space1, room1, space2]);

      final spaces = service.spaces;
      expect(spaces, hasLength(2));
      expect(spaces[0].getLocalizedDisplayname(), 'A Space');
      expect(spaces[1].getLocalizedDisplayname(), 'B Space');
    });
  });

  group('rooms getter', () {
    test('filters out spaces and sorts by last event timestamp', () {
      final space = MockRoom();
      when(space.isSpace).thenReturn(true);

      final olderRoom = MockRoom();
      when(olderRoom.isSpace).thenReturn(false);
      when(olderRoom.id).thenReturn('!old:example.com');
      when(olderRoom.lastEvent).thenReturn(_fakeEvent(
        room: olderRoom,
        ts: DateTime(2024, 1, 1),
      ));

      final newerRoom = MockRoom();
      when(newerRoom.isSpace).thenReturn(false);
      when(newerRoom.id).thenReturn('!new:example.com');
      when(newerRoom.lastEvent).thenReturn(_fakeEvent(
        room: newerRoom,
        ts: DateTime(2024, 6, 1),
      ));

      when(mockClient.rooms).thenReturn([space, olderRoom, newerRoom]);

      final rooms = service.rooms;
      expect(rooms, hasLength(2));
      // Newer first (descending)
      expect(rooms[0].id, '!new:example.com');
      expect(rooms[1].id, '!old:example.com');
    });

    test('filters by selected space children when space is selected', () {
      final childRoom = MockRoom();
      when(childRoom.isSpace).thenReturn(false);
      when(childRoom.id).thenReturn('!child:example.com');
      when(childRoom.lastEvent).thenReturn(null);

      final otherRoom = MockRoom();
      when(otherRoom.isSpace).thenReturn(false);
      when(otherRoom.id).thenReturn('!other:example.com');
      when(otherRoom.lastEvent).thenReturn(null);

      final space = MockRoom();
      when(space.isSpace).thenReturn(true);
      when(space.id).thenReturn('!space:example.com');
      when(space.spaceChildren).thenReturn([
        _fakeSpaceChild('!child:example.com'),
      ]);

      when(mockClient.rooms).thenReturn([space, childRoom, otherRoom]);
      when(mockClient.getRoomById('!space:example.com')).thenReturn(space);

      service.selectSpace('!space:example.com');

      final rooms = service.rooms;
      expect(rooms, hasLength(1));
      expect(rooms[0].id, '!child:example.com');
    });
  });

  group('login', () {
    test('returns true on success and persists credentials', () async {
      when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
            null,
            GetVersionsResponse.fromJson({'versions': ['v1.1']}),
            <LoginFlow>[],
            null,
          ));
      when(mockClient.login(
        any,
        identifier: anyNamed('identifier'),
        password: anyNamed('password'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).thenAnswer((_) async => LoginResponse.fromJson({
            'access_token': 'token123',
            'device_id': 'DEV1',
            'user_id': '@user:example.com',
          }));
      when(mockClient.accessToken).thenReturn('token123');
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockClient.homeserver).thenReturn(Uri.parse('https://example.com'));
      when(mockClient.deviceID).thenReturn('DEV1');
      final syncController = CachedStreamController<SyncUpdate>();
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());

      // Emit a sync event so _startSync() completes.
      Future.delayed(Duration.zero, () => syncController.add(SyncUpdate(nextBatch: 'batch1')));

      final result = await service.login(
        homeserver: 'example.com',
        username: 'user',
        password: 'pass',
      );

      expect(result, isTrue);
      expect(service.isLoggedIn, isTrue);
      verify(mockStorage.write(
              key: 'lattice_access_token', value: 'token123'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_user_id', value: '@user:example.com'))
          .called(1);
    });

    test('returns false on failure and sets loginError', () async {
      when(mockClient.checkHomeserver(any))
          .thenThrow(Exception('Connection refused'));

      final result = await service.login(
        homeserver: 'bad.server',
        username: 'user',
        password: 'pass',
      );

      expect(result, isFalse);
      expect(service.isLoggedIn, isFalse);
      expect(service.loginError, contains('Connection refused'));
    });
  });

  group('logout', () {
    test('deletes only session keys, not recovery key', () async {
      // First log in
      when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
            null,
            GetVersionsResponse.fromJson({'versions': ['v1.1']}),
            <LoginFlow>[],
            null,
          ));
      when(mockClient.login(
        any,
        identifier: anyNamed('identifier'),
        password: anyNamed('password'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).thenAnswer((_) async => LoginResponse.fromJson({
            'access_token': 'token123',
            'device_id': 'DEV1',
            'user_id': '@user:example.com',
          }));
      when(mockClient.accessToken).thenReturn('token123');
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockClient.homeserver).thenReturn(Uri.parse('https://example.com'));
      when(mockClient.deviceID).thenReturn('DEV1');
      final syncController = CachedStreamController<SyncUpdate>();
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());

      Future.delayed(Duration.zero, () => syncController.add(SyncUpdate(nextBatch: 'batch1')));
      await service.login(
        homeserver: 'example.com',
        username: 'user',
        password: 'pass',
      );
      service.selectSpace('!space:example.com');
      service.selectRoom('!room:example.com');

      await service.logout();

      expect(service.isLoggedIn, isFalse);
      expect(service.selectedSpaceId, isNull);
      expect(service.selectedRoomId, isNull);
      // Should delete individual session keys, NOT deleteAll
      verify(mockStorage.delete(key: 'lattice_access_token')).called(1);
      verify(mockStorage.delete(key: 'lattice_user_id')).called(1);
      verify(mockStorage.delete(key: 'lattice_homeserver')).called(1);
      verify(mockStorage.delete(key: 'lattice_device_id')).called(1);
      verify(mockStorage.delete(key: 'lattice_olm_account')).called(1);
      verifyNever(mockStorage.deleteAll());
    });
  });

  group('recovery key storage', () {
    test('storeRecoveryKey writes key to secure storage with user-scoped key',
        () async {
      when(mockClient.userID).thenReturn('@user:example.com');

      await service.storeRecoveryKey('my-recovery-key');

      verify(mockStorage.write(
        key: 'ssss_recovery_key_@user:example.com',
        value: 'my-recovery-key',
      )).called(1);
    });

    test('getStoredRecoveryKey reads from secure storage', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => 'stored-key');

      final result = await service.getStoredRecoveryKey();

      expect(result, 'stored-key');
    });

    test('getStoredRecoveryKey returns null when no userID', () async {
      when(mockClient.userID).thenReturn(null);

      final result = await service.getStoredRecoveryKey();

      expect(result, isNull);
    });

    test('deleteStoredRecoveryKey removes the key', () async {
      when(mockClient.userID).thenReturn('@user:example.com');

      await service.deleteStoredRecoveryKey();

      verify(mockStorage.delete(
        key: 'ssss_recovery_key_@user:example.com',
      )).called(1);
    });
  });

  group('chat backup', () {
    late MockEncryption mockEncryption;
    late MockCrossSigning mockCrossSigning;
    late MockKeyManager mockKeyManager;

    setUp(() {
      mockEncryption = MockEncryption();
      mockCrossSigning = MockCrossSigning();
      mockKeyManager = MockKeyManager();
      when(mockEncryption.crossSigning).thenReturn(mockCrossSigning);
      when(mockEncryption.keyManager).thenReturn(mockKeyManager);
    });

    group('checkChatBackupStatus', () {
      test('chatBackupNeeded is null initially (loading state)', () {
        expect(service.chatBackupNeeded, isNull);
      });

      test('sets chatBackupNeeded false when initialized and connected',
          () async {
        when(mockClient.encryption).thenReturn(mockEncryption);
        when(mockCrossSigning.enabled).thenReturn(true);
        when(mockKeyManager.enabled).thenReturn(true);
        when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
        when(mockKeyManager.isCached()).thenAnswer((_) async => true);

        await service.checkChatBackupStatus();

        expect(service.chatBackupNeeded, isFalse);
        expect(service.chatBackupEnabled, isTrue);
      });

      test('sets chatBackupNeeded true when client.encryption is null',
          () async {
        when(mockClient.encryption).thenReturn(null);

        await service.checkChatBackupStatus();

        expect(service.chatBackupNeeded, isTrue);
        expect(service.chatBackupEnabled, isFalse);
      });

      test('sets chatBackupNeeded true when cross-signing not cached',
          () async {
        when(mockClient.encryption).thenReturn(mockEncryption);
        when(mockCrossSigning.enabled).thenReturn(true);
        when(mockKeyManager.enabled).thenReturn(true);
        when(mockCrossSigning.isCached()).thenAnswer((_) async => false);
        when(mockKeyManager.isCached()).thenAnswer((_) async => true);

        await service.checkChatBackupStatus();

        expect(service.chatBackupNeeded, isTrue);
      });

      test('sets chatBackupNeeded true when key backup not enabled',
          () async {
        when(mockClient.encryption).thenReturn(mockEncryption);
        when(mockCrossSigning.enabled).thenReturn(true);
        when(mockKeyManager.enabled).thenReturn(false);

        await service.checkChatBackupStatus();

        expect(service.chatBackupNeeded, isTrue);
      });

      test('catches exceptions and sets chatBackupNeeded true', () async {
        when(mockClient.encryption).thenReturn(mockEncryption);
        when(mockKeyManager.enabled).thenThrow(Exception('network error'));

        await service.checkChatBackupStatus();

        expect(service.chatBackupNeeded, isTrue);
      });
    });

    group('disableChatBackup', () {
      test('calls deleteRoomKeysVersion and deletes stored recovery key',
          () async {
        when(mockClient.encryption).thenReturn(mockEncryption);
        when(mockClient.userID).thenReturn('@user:example.com');
        when(mockKeyManager.getRoomKeysBackupInfo()).thenAnswer((_) async =>
            GetRoomKeysVersionCurrentResponse(
              algorithm: BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2,
              authData: {},
              count: 0,
              etag: '1',
              version: '1',
            ));
        when(mockClient.deleteRoomKeysVersion('1'))
            .thenAnswer((_) async {});

        await service.disableChatBackup();

        verify(mockClient.deleteRoomKeysVersion('1')).called(1);
        verify(mockStorage.delete(
          key: 'ssss_recovery_key_@user:example.com',
        )).called(1);
      });

      test('sets user-friendly error on failure', () async {
        when(mockClient.encryption).thenReturn(mockEncryption);
        when(mockKeyManager.getRoomKeysBackupInfo())
            .thenThrow(Exception('Network error'));

        await service.disableChatBackup();

        expect(service.chatBackupError,
            'Failed to disable chat backup. Please try again.');
      });
    });
  });

  group('sync subscription', () {
    test('cancels sync subscriptions on dispose', () async {
      when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
            null,
            GetVersionsResponse.fromJson({'versions': ['v1.1']}),
            <LoginFlow>[],
            null,
          ));
      when(mockClient.login(
        any,
        identifier: anyNamed('identifier'),
        password: anyNamed('password'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).thenAnswer((_) async => LoginResponse.fromJson({
            'access_token': 'token123',
            'device_id': 'DEV1',
            'user_id': '@user:example.com',
          }));
      when(mockClient.accessToken).thenReturn('token123');
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockClient.homeserver).thenReturn(Uri.parse('https://example.com'));
      when(mockClient.deviceID).thenReturn('DEV1');
      final syncController = CachedStreamController<SyncUpdate>();
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());

      Future.delayed(Duration.zero, () => syncController.add(SyncUpdate(nextBatch: 'batch1')));
      await service.login(
        homeserver: 'example.com',
        username: 'user',
        password: 'pass',
      );

      // Should not throw
      service.dispose();
    });
  });
}

/// Creates a real [Event] with the given timestamp.
Event _fakeEvent({required Room room, required DateTime ts}) {
  return Event(
    content: {'body': 'test', 'msgtype': 'm.text'},
    type: EventTypes.Message,
    eventId: '\$evt_${ts.millisecondsSinceEpoch}',
    senderId: '@user:example.com',
    originServerTs: ts,
    room: room,
  );
}

/// Creates a [SpaceChild] from a synthetic state event.
SpaceChild _fakeSpaceChild(String roomId) {
  return SpaceChild.fromState(StrippedStateEvent(
    type: EventTypes.SpaceChild,
    content: {'via': ['example.com']},
    senderId: '@admin:example.com',
    stateKey: roomId,
  ));
}

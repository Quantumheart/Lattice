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
    service = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
  });

  group('selectSpace', () {
    test('updates selectedSpaceIds and notifies listeners', () {
      var notified = false;
      service.addListener(() => notified = true);

      service.selectSpace('!space:example.com');

      expect(service.selectedSpaceIds, {'!space:example.com'});
      expect(notified, isTrue);
    });

    test('can be cleared to null', () {
      service.selectSpace('!space:example.com');
      service.selectSpace(null);

      expect(service.selectedSpaceIds, isEmpty);
    });

    test('clears when selecting the only selected space again', () {
      service.selectSpace('!space:example.com');
      service.selectSpace('!space:example.com');

      expect(service.selectedSpaceIds, isEmpty);
    });

    test('replaces previous selection', () {
      service.selectSpace('!a:example.com');
      service.selectSpace('!b:example.com');

      expect(service.selectedSpaceIds, {'!b:example.com'});
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
      when(space1.membership).thenReturn(Membership.join);
      when(space1.getLocalizedDisplayname()).thenReturn('B Space');

      final space2 = MockRoom();
      when(space2.isSpace).thenReturn(true);
      when(space2.membership).thenReturn(Membership.join);
      when(space2.getLocalizedDisplayname()).thenReturn('A Space');

      final room1 = MockRoom();
      when(room1.isSpace).thenReturn(false);
      when(room1.membership).thenReturn(Membership.join);

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
      when(space.membership).thenReturn(Membership.join);

      final olderRoom = MockRoom();
      when(olderRoom.isSpace).thenReturn(false);
      when(olderRoom.membership).thenReturn(Membership.join);
      when(olderRoom.id).thenReturn('!old:example.com');
      when(olderRoom.lastEvent).thenReturn(_fakeEvent(
        room: olderRoom,
        ts: DateTime(2024, 1, 1),
      ));

      final newerRoom = MockRoom();
      when(newerRoom.isSpace).thenReturn(false);
      when(newerRoom.membership).thenReturn(Membership.join);
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

    test('returns all non-space rooms regardless of space selection', () {
      final childRoom = MockRoom();
      when(childRoom.isSpace).thenReturn(false);
      when(childRoom.membership).thenReturn(Membership.join);
      when(childRoom.id).thenReturn('!child:example.com');
      when(childRoom.lastEvent).thenReturn(null);

      final otherRoom = MockRoom();
      when(otherRoom.isSpace).thenReturn(false);
      when(otherRoom.membership).thenReturn(Membership.join);
      when(otherRoom.id).thenReturn('!other:example.com');
      when(otherRoom.lastEvent).thenReturn(null);

      final space = MockRoom();
      when(space.isSpace).thenReturn(true);
      when(space.membership).thenReturn(Membership.join);
      when(space.id).thenReturn('!space:example.com');
      when(space.spaceChildren).thenReturn([
        _fakeSpaceChild('!child:example.com'),
      ]);

      when(mockClient.rooms).thenReturn([space, childRoom, otherRoom]);
      when(mockClient.getRoomById('!space:example.com')).thenReturn(space);

      service.selectSpace('!space:example.com');

      final rooms = service.rooms;
      expect(rooms, hasLength(2));
    });
  });

  group('login', () {
    test('returns true on success and persists credentials with namespaced keys',
        () async {
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
      when(mockClient.encryption).thenReturn(null);
      final syncController = CachedStreamController<SyncUpdate>();
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
      when(mockClient.onLoginStateChanged).thenReturn(CachedStreamController());

      // Emit a sync event so _startSync() completes.
      Future.delayed(Duration.zero, () => syncController.add(SyncUpdate(nextBatch: 'batch1')));

      final result = await service.login(
        homeserver: 'example.com',
        username: 'user',
        password: 'pass',
      );

      expect(result, isTrue);
      expect(service.isLoggedIn, isTrue);
      // Verify namespaced storage keys.
      verify(mockStorage.write(
              key: 'lattice_test_access_token', value: 'token123'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_test_user_id', value: '@user:example.com'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_test_homeserver', value: 'https://example.com'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_test_device_id', value: 'DEV1'))
          .called(1);
      // Verify session backup is saved.
      verify(mockStorage.write(
        key: 'lattice_session_backup_test',
        value: anyNamed('value'),
      )).called(1);
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
    test('deletes session keys and session backup', () async {
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
      when(mockClient.encryption).thenReturn(null);
      final syncController = CachedStreamController<SyncUpdate>();
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
      when(mockClient.onLoginStateChanged).thenReturn(CachedStreamController());

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
      expect(service.selectedSpaceIds, isEmpty);
      expect(service.selectedRoomId, isNull);
      // Verify namespaced key deletion.
      verify(mockStorage.delete(key: 'lattice_test_access_token')).called(1);
      verify(mockStorage.delete(key: 'lattice_test_user_id')).called(1);
      verify(mockStorage.delete(key: 'lattice_test_homeserver')).called(1);
      verify(mockStorage.delete(key: 'lattice_test_device_id')).called(1);
      verify(mockStorage.delete(key: 'lattice_test_olm_account')).called(1);
      // Verify session backup is deleted.
      verify(mockStorage.delete(key: 'lattice_session_backup_test')).called(1);
      verifyNever(mockStorage.deleteAll());
    });
  });

  group('soft logout', () {
    late CachedStreamController<SyncUpdate> syncController;
    late CachedStreamController<LoginState> loginStateController;

    setUp(() {
      syncController = CachedStreamController<SyncUpdate>();
      loginStateController = CachedStreamController<LoginState>();
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
      when(mockClient.encryption).thenReturn(null);
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
      when(mockClient.onLoginStateChanged).thenReturn(loginStateController);
    });

    test('server-side logout clears state and notifies listeners', () async {
      Future.delayed(Duration.zero, () => syncController.add(SyncUpdate(nextBatch: 'batch1')));
      await service.login(
        homeserver: 'example.com',
        username: 'user',
        password: 'pass',
      );
      expect(service.isLoggedIn, isTrue);

      var notified = false;
      service.addListener(() => notified = true);

      // Simulate server-side logout.
      loginStateController.add(LoginState.loggedOut);
      await Future.delayed(Duration.zero);

      expect(service.isLoggedIn, isFalse);
      expect(service.selectedSpaceIds, isEmpty);
      expect(service.selectedRoomId, isNull);
      expect(notified, isTrue);
    });

    test('duplicate loggedIn event while logged in is idempotent', () async {
      Future.delayed(Duration.zero, () => syncController.add(SyncUpdate(nextBatch: 'batch1')));
      await service.login(
        homeserver: 'example.com',
        username: 'user',
        password: 'pass',
      );

      var notifyCount = 0;
      service.addListener(() => notifyCount++);

      // Emit loggedIn — should not change state.
      loginStateController.add(LoginState.loggedIn);
      await Future.delayed(Duration.zero);

      expect(service.isLoggedIn, isTrue);
      expect(notifyCount, 0);
    });
  });

  group('login state subscription cleanup', () {
    test('dispose cancels login state subscription without errors', () async {
      final syncController = CachedStreamController<SyncUpdate>();
      final loginStateController = CachedStreamController<LoginState>();
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
      when(mockClient.encryption).thenReturn(null);
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
      when(mockClient.onLoginStateChanged).thenReturn(loginStateController);

      Future.delayed(Duration.zero, () => syncController.add(SyncUpdate(nextBatch: 'batch1')));
      await service.login(
        homeserver: 'example.com',
        username: 'user',
        password: 'pass',
      );

      // Should not throw.
      service.dispose();

      // Emitting after dispose should not cause errors.
      loginStateController.add(LoginState.loggedOut);
      await Future.delayed(Duration.zero);
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

  group('clientName', () {
    test('defaults to "default"', () {
      final defaultService = MatrixService(
        client: mockClient,
        storage: mockStorage,
      );
      expect(defaultService.clientName, 'default');
    });

    test('accepts custom clientName', () {
      expect(service.clientName, 'test');
    });
  });

  group('toggleSpaceSelection', () {
    test('adds space to selection', () {
      service.toggleSpaceSelection('!a:example.com');

      expect(service.selectedSpaceIds, {'!a:example.com'});
    });

    test('removes space if already selected', () {
      service.toggleSpaceSelection('!a:example.com');
      service.toggleSpaceSelection('!a:example.com');

      expect(service.selectedSpaceIds, isEmpty);
    });

    test('supports multi-select', () {
      service.toggleSpaceSelection('!a:example.com');
      service.toggleSpaceSelection('!b:example.com');

      expect(service.selectedSpaceIds, {'!a:example.com', '!b:example.com'});
    });
  });

  group('clearSpaceSelection', () {
    test('empties the selected set', () {
      service.selectSpace('!a:example.com');
      service.clearSpaceSelection();

      expect(service.selectedSpaceIds, isEmpty);
    });
  });

  group('invitedRooms', () {
    test('returns only non-space rooms with invite membership, sorted alphabetically', () {
      final invitedRoom1 = MockRoom();
      when(invitedRoom1.isSpace).thenReturn(false);
      when(invitedRoom1.membership).thenReturn(Membership.invite);
      when(invitedRoom1.getLocalizedDisplayname()).thenReturn('B Room');

      final invitedRoom2 = MockRoom();
      when(invitedRoom2.isSpace).thenReturn(false);
      when(invitedRoom2.membership).thenReturn(Membership.invite);
      when(invitedRoom2.getLocalizedDisplayname()).thenReturn('A Room');

      final joinedRoom = MockRoom();
      when(joinedRoom.isSpace).thenReturn(false);
      when(joinedRoom.membership).thenReturn(Membership.join);

      final invitedSpace = MockRoom();
      when(invitedSpace.isSpace).thenReturn(true);
      when(invitedSpace.membership).thenReturn(Membership.invite);

      when(mockClient.rooms).thenReturn([invitedRoom1, joinedRoom, invitedRoom2, invitedSpace]);

      final result = service.invitedRooms;
      expect(result, hasLength(2));
      expect(result[0].getLocalizedDisplayname(), 'A Room');
      expect(result[1].getLocalizedDisplayname(), 'B Room');
    });

    test('returns empty list when no invites', () {
      final joinedRoom = MockRoom();
      when(joinedRoom.isSpace).thenReturn(false);
      when(joinedRoom.membership).thenReturn(Membership.join);

      when(mockClient.rooms).thenReturn([joinedRoom]);

      expect(service.invitedRooms, isEmpty);
    });
  });

  group('invitedSpaces', () {
    test('returns only spaces with invite membership, sorted alphabetically', () {
      final invitedSpace1 = MockRoom();
      when(invitedSpace1.isSpace).thenReturn(true);
      when(invitedSpace1.membership).thenReturn(Membership.invite);
      when(invitedSpace1.getLocalizedDisplayname()).thenReturn('Z Space');

      final invitedSpace2 = MockRoom();
      when(invitedSpace2.isSpace).thenReturn(true);
      when(invitedSpace2.membership).thenReturn(Membership.invite);
      when(invitedSpace2.getLocalizedDisplayname()).thenReturn('A Space');

      final invitedRoom = MockRoom();
      when(invitedRoom.isSpace).thenReturn(false);
      when(invitedRoom.membership).thenReturn(Membership.invite);

      final joinedSpace = MockRoom();
      when(joinedSpace.isSpace).thenReturn(true);
      when(joinedSpace.membership).thenReturn(Membership.join);

      when(mockClient.rooms).thenReturn([invitedSpace1, invitedRoom, joinedSpace, invitedSpace2]);

      final result = service.invitedSpaces;
      expect(result, hasLength(2));
      expect(result[0].getLocalizedDisplayname(), 'A Space');
      expect(result[1].getLocalizedDisplayname(), 'Z Space');
    });
  });

  group('inviterDisplayName', () {
    test('returns display name of the inviter', () {
      final room = MockRoom();
      when(room.client).thenReturn(mockClient);
      when(mockClient.userID).thenReturn('@me:example.com');

      final inviteEvent = Event(
        type: EventTypes.RoomMember,
        content: {'membership': 'invite'},
        eventId: '\$invite1',
        senderId: '@alice:example.com',
        originServerTs: DateTime.now(),
        room: room,
        stateKey: '@me:example.com',
      );
      when(room.getState(EventTypes.RoomMember, '@me:example.com'))
          .thenReturn(inviteEvent);
      when(room.unsafeGetUserFromMemoryOrFallback('@alice:example.com'))
          .thenReturn(User('@alice:example.com', room: room, displayName: 'Alice'));

      final result = service.inviterDisplayName(room);
      expect(result, 'Alice');
    });

    test('returns null when no userID', () {
      final room = MockRoom();
      when(mockClient.userID).thenReturn(null);

      expect(service.inviterDisplayName(room), isNull);
    });

    test('returns null when no invite state event', () {
      final room = MockRoom();
      when(mockClient.userID).thenReturn('@me:example.com');
      when(room.getState(EventTypes.RoomMember, '@me:example.com'))
          .thenReturn(null);

      expect(service.inviterDisplayName(room), isNull);
    });
  });

  group('space tree', () {
    late MockRoom spaceA;
    late MockRoom spaceB;
    late MockRoom subspace;
    late MockRoom room1;
    late MockRoom room2;
    late MockRoom room3;
    late MockRoom orphanRoom;

    setUp(() {
      // Space A contains room1 and subspace
      spaceA = MockRoom();
      when(spaceA.isSpace).thenReturn(true);
      when(spaceA.membership).thenReturn(Membership.join);
      when(spaceA.id).thenReturn('!spaceA:example.com');
      when(spaceA.getLocalizedDisplayname()).thenReturn('A Space');

      // Subspace (child of A) contains room2
      subspace = MockRoom();
      when(subspace.isSpace).thenReturn(true);
      when(subspace.membership).thenReturn(Membership.join);
      when(subspace.id).thenReturn('!subspace:example.com');
      when(subspace.getLocalizedDisplayname()).thenReturn('Sub Space');

      // Space B contains room3
      spaceB = MockRoom();
      when(spaceB.isSpace).thenReturn(true);
      when(spaceB.membership).thenReturn(Membership.join);
      when(spaceB.id).thenReturn('!spaceB:example.com');
      when(spaceB.getLocalizedDisplayname()).thenReturn('B Space');

      room1 = MockRoom();
      when(room1.isSpace).thenReturn(false);
      when(room1.membership).thenReturn(Membership.join);
      when(room1.id).thenReturn('!room1:example.com');
      when(room1.lastEvent).thenReturn(null);
      when(room1.notificationCount).thenReturn(3);

      room2 = MockRoom();
      when(room2.isSpace).thenReturn(false);
      when(room2.membership).thenReturn(Membership.join);
      when(room2.id).thenReturn('!room2:example.com');
      when(room2.lastEvent).thenReturn(null);
      when(room2.notificationCount).thenReturn(5);

      room3 = MockRoom();
      when(room3.isSpace).thenReturn(false);
      when(room3.membership).thenReturn(Membership.join);
      when(room3.id).thenReturn('!room3:example.com');
      when(room3.lastEvent).thenReturn(null);
      when(room3.notificationCount).thenReturn(0);

      orphanRoom = MockRoom();
      when(orphanRoom.isSpace).thenReturn(false);
      when(orphanRoom.membership).thenReturn(Membership.join);
      when(orphanRoom.id).thenReturn('!orphan:example.com');
      when(orphanRoom.lastEvent).thenReturn(null);
      when(orphanRoom.notificationCount).thenReturn(1);

      // Wire up space children
      when(spaceA.spaceChildren).thenReturn([
        _fakeSpaceChild('!room1:example.com'),
        _fakeSpaceChild('!subspace:example.com'),
      ]);
      when(subspace.spaceChildren).thenReturn([
        _fakeSpaceChild('!room2:example.com'),
      ]);
      when(spaceB.spaceChildren).thenReturn([
        _fakeSpaceChild('!room3:example.com'),
      ]);

      when(mockClient.rooms).thenReturn([
        spaceA, spaceB, subspace, room1, room2, room3, orphanRoom,
      ]);
      when(mockClient.getRoomById('!spaceA:example.com')).thenReturn(spaceA);
      when(mockClient.getRoomById('!spaceB:example.com')).thenReturn(spaceB);
      when(mockClient.getRoomById('!subspace:example.com')).thenReturn(subspace);
      when(mockClient.getRoomById('!room1:example.com')).thenReturn(room1);
      when(mockClient.getRoomById('!room2:example.com')).thenReturn(room2);
      when(mockClient.getRoomById('!room3:example.com')).thenReturn(room3);
      when(mockClient.getRoomById('!orphan:example.com')).thenReturn(orphanRoom);
    });

    test('builds correctly with nested subspaces', () {
      final tree = service.spaceTree;

      expect(tree, hasLength(2)); // A Space and B Space (top-level)
      expect(tree[0].room.id, '!spaceA:example.com'); // A before B
      expect(tree[1].room.id, '!spaceB:example.com');

      // A Space has subspace
      expect(tree[0].subspaces, hasLength(1));
      expect(tree[0].subspaces[0].room.id, '!subspace:example.com');
      expect(tree[0].directChildRoomIds, ['!room1:example.com']);

      // Subspace has room2
      expect(tree[0].subspaces[0].directChildRoomIds, ['!room2:example.com']);

      // B Space has room3, no subspaces
      expect(tree[1].subspaces, isEmpty);
      expect(tree[1].directChildRoomIds, ['!room3:example.com']);
    });

    test('unjoined subspace children are ignored gracefully', () {
      // Add a reference to an unjoined space
      when(spaceA.spaceChildren).thenReturn([
        _fakeSpaceChild('!room1:example.com'),
        _fakeSpaceChild('!subspace:example.com'),
        _fakeSpaceChild('!unjoined:example.com'), // not in client.rooms
      ]);
      when(mockClient.getRoomById('!unjoined:example.com')).thenReturn(null);

      final tree = service.spaceTree;

      // Should still build correctly, ignoring unjoined
      expect(tree, hasLength(2));
      expect(tree[0].subspaces, hasLength(1));
    });

    test('orphanRooms excludes rooms in any space', () {
      final orphans = service.orphanRooms;

      expect(orphans, hasLength(1));
      expect(orphans[0].id, '!orphan:example.com');
    });

    test('roomsForSpace returns correct children', () {
      final roomsA = service.roomsForSpace('!spaceA:example.com');
      expect(roomsA, hasLength(1));
      expect(roomsA[0].id, '!room1:example.com');

      final roomsSub = service.roomsForSpace('!subspace:example.com');
      expect(roomsSub, hasLength(1));
      expect(roomsSub[0].id, '!room2:example.com');

      final roomsB = service.roomsForSpace('!spaceB:example.com');
      expect(roomsB, hasLength(1));
      expect(roomsB[0].id, '!room3:example.com');
    });

    test('spaceMemberships returns correct set', () {
      final memberships1 = service.spaceMemberships('!room1:example.com');
      expect(memberships1, {'!spaceA:example.com'});

      final memberships2 = service.spaceMemberships('!room2:example.com');
      expect(memberships2, {'!subspace:example.com'});

      // Orphan room has no memberships
      final orphanMemberships = service.spaceMemberships('!orphan:example.com');
      expect(orphanMemberships, isEmpty);
    });

    test('unreadCountForSpace aggregates correctly', () {
      // Space A: room1 (3) + subspace room2 (5) = 8
      expect(service.unreadCountForSpace('!spaceA:example.com'), 8);

      // Subspace alone: room2 (5) = 5
      expect(service.unreadCountForSpace('!subspace:example.com'), 5);

      // Space B: room3 (0) = 0
      expect(service.unreadCountForSpace('!spaceB:example.com'), 0);

      // Non-existent space = 0
      expect(service.unreadCountForSpace('!nonexistent:example.com'), 0);
    });

    test('rooms getter returns all non-space rooms unfiltered', () {
      service.selectSpace('!spaceA:example.com');

      final allRooms = service.rooms;
      expect(allRooms, hasLength(4)); // room1, room2, room3, orphanRoom
    });

    test('updateSpaceOrder changes ordering of spaces getter', () {
      // Default: alphabetical → A Space, B Space
      expect(service.spaces[0].id, '!spaceA:example.com');
      expect(service.spaces[1].id, '!spaceB:example.com');

      // Custom: B before A
      service.updateSpaceOrder([
        '!spaceB:example.com',
        '!spaceA:example.com',
      ]);

      expect(service.spaces[0].id, '!spaceB:example.com');
      expect(service.spaces[1].id, '!spaceA:example.com');
    });

    test('updateSpaceOrder changes ordering of top-level spaceTree', () {
      service.updateSpaceOrder([
        '!spaceB:example.com',
        '!spaceA:example.com',
      ]);

      final tree = service.spaceTree;
      expect(tree[0].room.id, '!spaceB:example.com');
      expect(tree[1].room.id, '!spaceA:example.com');
    });

    test('subspace ordering remains alphabetical regardless of custom order',
        () {
      // Add a second subspace to Space A
      final subspace2 = MockRoom();
      when(subspace2.isSpace).thenReturn(true);
      when(subspace2.membership).thenReturn(Membership.join);
      when(subspace2.id).thenReturn('!subspace2:example.com');
      when(subspace2.getLocalizedDisplayname()).thenReturn('A Sub');
      when(subspace2.spaceChildren).thenReturn([]);
      when(mockClient.getRoomById('!subspace2:example.com'))
          .thenReturn(subspace2);

      when(spaceA.spaceChildren).thenReturn([
        _fakeSpaceChild('!room1:example.com'),
        _fakeSpaceChild('!subspace:example.com'),
        _fakeSpaceChild('!subspace2:example.com'),
      ]);
      when(mockClient.rooms).thenReturn([
        spaceA, spaceB, subspace, subspace2, room1, room2, room3, orphanRoom,
      ]);

      // Custom order only affects top-level; subspaces stay alphabetical
      service.updateSpaceOrder([
        '!subspace:example.com', // stale — subspace is not top-level
        '!spaceB:example.com',
        '!spaceA:example.com',
      ]);

      final tree = service.spaceTree;
      final aSubs = tree.firstWhere(
          (n) => n.room.id == '!spaceA:example.com').subspaces;
      expect(aSubs[0].room.getLocalizedDisplayname(), 'A Sub');
      expect(aSubs[1].room.getLocalizedDisplayname(), 'Sub Space');
    });

    test('new spaces not in custom order appear at the end alphabetically',
        () {
      // Order only mentions B — A should appear after B alphabetically
      service.updateSpaceOrder(['!spaceB:example.com']);

      expect(service.spaces[0].id, '!spaceB:example.com');
      expect(service.spaces[1].id, '!spaceA:example.com');

      // Also in the subspace list — subspace is not top-level so it's
      // irrelevant, but if we add a new top-level space C:
      final spaceC = MockRoom();
      when(spaceC.isSpace).thenReturn(true);
      when(spaceC.membership).thenReturn(Membership.join);
      when(spaceC.id).thenReturn('!spaceC:example.com');
      when(spaceC.getLocalizedDisplayname()).thenReturn('C Space');
      when(spaceC.spaceChildren).thenReturn([]);
      when(mockClient.getRoomById('!spaceC:example.com')).thenReturn(spaceC);
      when(mockClient.rooms).thenReturn([
        spaceA, spaceB, spaceC, subspace, room1, room2, room3, orphanRoom,
      ]);

      // Force tree rebuild
      service.updateSpaceOrder(['!spaceB:example.com', '!spaceA:example.com']);

      final spaces = service.spaces;
      // B first, A second (both in order), C last (not in order)
      expect(spaces[0].id, '!spaceB:example.com');
      expect(spaces[1].id, '!spaceA:example.com');
      expect(spaces[2].id, '!spaceC:example.com');
    });

    test('stale IDs in custom order are silently ignored', () {
      service.updateSpaceOrder([
        '!nonexistent:example.com', // stale — doesn't exist
        '!spaceB:example.com',
        '!spaceA:example.com',
      ]);

      // Should work fine, ignoring the stale ID
      final spaces = service.spaces;
      expect(spaces, hasLength(3)); // A, B, subspace
      expect(spaces[0].id, '!spaceB:example.com');
      expect(spaces[1].id, '!spaceA:example.com');
    });

    test('updateSpaceOrder with identical list is a no-op', () {
      service.updateSpaceOrder([
        '!spaceB:example.com',
        '!spaceA:example.com',
      ]);

      var notifyCount = 0;
      service.addListener(() => notifyCount++);

      // Same order again — should not notify
      service.updateSpaceOrder([
        '!spaceB:example.com',
        '!spaceA:example.com',
      ]);

      expect(notifyCount, 0);
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
      when(mockClient.encryption).thenReturn(null);
      final syncController = CachedStreamController<SyncUpdate>();
      when(mockClient.onSync).thenReturn(syncController);
      when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
      when(mockClient.onLoginStateChanged).thenReturn(CachedStreamController());

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

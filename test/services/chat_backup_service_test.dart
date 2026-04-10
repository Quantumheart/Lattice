import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/sub_services/chat_backup_service.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MockEncryption mockEncryption;
  late MockCrossSigning mockCrossSigning;
  late MockKeyManager mockKeyManager;
  late MockSSSS mockSsss;
  late ChatBackupService service;
  late int changeCount;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    mockEncryption = MockEncryption();
    mockCrossSigning = MockCrossSigning();
    mockKeyManager = MockKeyManager();
    mockSsss = MockSSSS();
    changeCount = 0;
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.encryption).thenReturn(mockEncryption);
    when(mockEncryption.crossSigning).thenReturn(mockCrossSigning);
    when(mockEncryption.keyManager).thenReturn(mockKeyManager);
    when(mockEncryption.ssss).thenReturn(mockSsss);
    when(mockKeyManager.getRoomKeysBackupInfo(any)).thenAnswer(
      (_) async => GetRoomKeysVersionCurrentResponse.fromJson({
        'algorithm': BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2.name,
        'auth_data': <String, dynamic>{'public_key': 'fake'},
        'count': 0,
        'etag': '0',
        'version': '1',
      }),
    );
    service = ChatBackupService(
      client: mockClient,
      storage: mockStorage,
    );
    service.addListener(() => changeCount++);
  });

  group('checkChatBackupStatus', () {
    test('sets chatBackupNeeded false when initialized and connected',
        () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);

      await service.checkChatBackupStatus();

      expect(service.chatBackupNeeded, isFalse);
      expect(service.chatBackupEnabled, isTrue);
      expect(changeCount, greaterThan(0));
    });

    test('sets chatBackupNeeded true when not initialized', () async {
      when(mockCrossSigning.enabled).thenReturn(false);
      when(mockKeyManager.enabled).thenReturn(false);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => false);
      when(mockKeyManager.isCached()).thenAnswer((_) async => false);

      await service.checkChatBackupStatus();

      expect(service.chatBackupNeeded, isTrue);
    });

    test('sets chatBackupNeeded true on error', () async {
      when(mockClient.encryption).thenReturn(null);

      await service.checkChatBackupStatus();

      expect(service.chatBackupNeeded, isTrue);
      expect(changeCount, greaterThan(0));
    });
  });

  group('tryAutoUnlockBackup', () {
    test('checks backup status even when no stored recovery key', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => null);
      when(mockCrossSigning.enabled).thenReturn(false);
      when(mockKeyManager.enabled).thenReturn(false);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => false);
      when(mockKeyManager.isCached()).thenAnswer((_) async => false);

      await service.tryAutoUnlockBackup();

      expect(service.chatBackupNeeded, isTrue);
    });

    test('skips restore when already connected', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => 'recovery-key');
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);

      await service.tryAutoUnlockBackup();

      expect(service.chatBackupNeeded, isFalse);
    });

    test('handles errors silently', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => 'recovery-key');
      when(mockClient.encryption).thenReturn(null);

      await service.tryAutoUnlockBackup();

      expect(service.chatBackupNeeded, isTrue);
    });

    test('requests missing room keys when no stored key', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => null);
      when(mockCrossSigning.enabled).thenReturn(false);
      when(mockKeyManager.enabled).thenReturn(false);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => false);
      when(mockKeyManager.isCached()).thenAnswer((_) async => false);

      final mockRoom = MockRoom();
      when(mockClient.rooms).thenReturn([mockRoom]);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.lastEvent).thenReturn(Event(
        type: EventTypes.Encrypted,
        content: {
          'msgtype': MessageTypes.BadEncrypted,
          'can_request_session': true,
          'session_id': 'session123',
          'sender_key': 'key456',
        },
        senderId: '@user:example.com',
        eventId: r'$ev1',
        originServerTs: DateTime.now(),
        room: mockRoom,
      ),);

      await service.tryAutoUnlockBackup();

      verify(
        mockKeyManager.maybeAutoRequest(
          '!room:example.com',
          'session123',
          'key456',
        ),
      ).called(1);
    });
  });

  group('recovery key storage', () {
    test('getStoredRecoveryKey reads from storage', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockStorage.read(key: 'ssss_recovery_key_@user:example.com'))
          .thenAnswer((_) async => 'test-key');

      final key = await service.getStoredRecoveryKey();

      expect(key, 'test-key');
    });

    test('storeRecoveryKey writes to storage', () async {
      when(mockClient.userID).thenReturn('@user:example.com');

      await service.storeRecoveryKey('new-key');

      verify(
        mockStorage.write(
          key: 'ssss_recovery_key_@user:example.com',
          value: 'new-key',
        ),
      ).called(1);
    });

    test('deleteStoredRecoveryKey deletes from storage', () async {
      when(mockClient.userID).thenReturn('@user:example.com');

      await service.deleteStoredRecoveryKey();

      verify(
        mockStorage.delete(
          key: 'ssss_recovery_key_@user:example.com',
        ),
      ).called(1);
    });

    test('getStoredRecoveryKey returns null when no userID', () async {
      when(mockClient.userID).thenReturn(null);

      final key = await service.getStoredRecoveryKey();

      expect(key, isNull);
    });
  });

  group('disableChatBackup', () {
    test('handles M_NOT_FOUND gracefully', () async {
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockKeyManager.getRoomKeysBackupInfo()).thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_NOT_FOUND',
          'error': 'No backup found',
        }),
      );

      await service.disableChatBackup();

      expect(service.chatBackupNeeded, isTrue);
      expect(service.chatBackupError, isNull);
      expect(service.chatBackupLoading, isFalse);
    });

    test('sets error on failure', () async {
      when(mockClient.encryption).thenReturn(null);

      await service.disableChatBackup();

      expect(service.chatBackupError, isNotNull);
      expect(service.chatBackupLoading, isFalse);
    });
  });

  group('resetChatBackupState', () {
    test('resets chatBackupNeeded to null', () async {
      when(mockCrossSigning.enabled).thenReturn(true);
      when(mockKeyManager.enabled).thenReturn(true);
      when(mockCrossSigning.isCached()).thenAnswer((_) async => true);
      when(mockKeyManager.isCached()).thenAnswer((_) async => true);

      await service.checkChatBackupStatus();
      expect(service.chatBackupNeeded, isFalse);

      service.resetChatBackupState();

      expect(service.chatBackupNeeded, isNull);
    });
  });

  group('requestMissingRoomKeys', () {
    test('is a no-op when encryption is null', () {
      when(mockClient.encryption).thenReturn(null);

      service.requestMissingRoomKeys();
    });

    test('requests keys for undecryptable events', () {
      final mockRoom = MockRoom();
      when(mockClient.rooms).thenReturn([mockRoom]);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.lastEvent).thenReturn(Event(
        type: EventTypes.Encrypted,
        content: {
          'msgtype': MessageTypes.BadEncrypted,
          'can_request_session': true,
          'session_id': 'session123',
          'sender_key': 'key456',
        },
        senderId: '@user:example.com',
        eventId: r'$ev1',
        originServerTs: DateTime.now(),
        room: mockRoom,
      ),);

      service.requestMissingRoomKeys();

      verify(
        mockKeyManager.maybeAutoRequest(
          '!room:example.com',
          'session123',
          'key456',
        ),
      ).called(1);
    });
  });
}

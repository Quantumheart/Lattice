import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/backup_version_manager.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockEncryption mockEncryption;
  late MockKeyManager mockKeyManager;
  late MockSSSS mockSsss;
  late MockDatabaseApi mockDatabase;
  late BackupVersionManager manager;

  GetRoomKeysVersionCurrentResponse fakeInfo() =>
      GetRoomKeysVersionCurrentResponse.fromJson({
        'algorithm': BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2.name,
        'auth_data': <String, dynamic>{'public_key': 'fake'},
        'count': 0,
        'etag': '0',
        'version': '1',
      });

  setUp(() {
    mockClient = MockClient();
    mockEncryption = MockEncryption();
    mockKeyManager = MockKeyManager();
    mockSsss = MockSSSS();
    mockDatabase = MockDatabaseApi();
    when(mockClient.encryption).thenReturn(mockEncryption);
    when(mockClient.database).thenReturn(mockDatabase);
    when(mockEncryption.keyManager).thenReturn(mockKeyManager);
    when(mockEncryption.ssss).thenReturn(mockSsss);
    manager = BackupVersionManager(client: mockClient);
  });

  test('returns fetched info when server has a version', () async {
    when(mockKeyManager.getRoomKeysBackupInfo(any))
        .thenAnswer((_) async => fakeInfo());

    final result = await manager.ensureExists();

    expect(result, isNotNull);
    expect(result!.version, '1');
    verifyNever(mockClient.postRoomKeysVersion(any, any));
  });

  test('returns null when encryption is unavailable', () async {
    when(mockClient.encryption).thenReturn(null);

    final result = await manager.ensureExists();

    expect(result, isNull);
    verifyNever(mockKeyManager.getRoomKeysBackupInfo(any));
  });

  test('returns null on non-M_NOT_FOUND Matrix error', () async {
    when(mockKeyManager.getRoomKeysBackupInfo(any)).thenThrow(
      MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Not allowed',
      }),
    );

    final result = await manager.ensureExists();

    expect(result, isNull);
    verifyNever(mockClient.postRoomKeysVersion(any, any));
  });

  test('returns null on unexpected exception', () async {
    when(mockKeyManager.getRoomKeysBackupInfo(any))
        .thenThrow(Exception('network'));

    final result = await manager.ensureExists();

    expect(result, isNull);
    verifyNever(mockClient.postRoomKeysVersion(any, any));
  });

  test('returns null when M_NOT_FOUND and no cached megolm secret', () async {
    when(mockKeyManager.getRoomKeysBackupInfo(any)).thenThrow(
      MatrixException.fromJson({
        'errcode': 'M_NOT_FOUND',
        'error': 'Unknown backup version',
      }),
    );
    when(mockSsss.getCached(EventTypes.MegolmBackup))
        .thenAnswer((_) async => null);

    final result = await manager.ensureExists();

    expect(result, isNull);
    verifyNever(mockClient.postRoomKeysVersion(any, any));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/e2ee/widgets/key_backup_signer.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/olm_manager.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Encryption>(),
  MockSpec<OpenSSSS>(),
  MockSpec<KeyManager>(),
  MockSpec<OlmManager>(),
])
import 'key_backup_signer_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockEncryption mockEncryption;
  late MockOpenSSSS mockSsssKey;
  late MockKeyManager mockKeyManager;

  setUp(() {
    mockClient = MockClient();
    mockEncryption = MockEncryption();
    mockSsssKey = MockOpenSSSS();
    mockKeyManager = MockKeyManager();
    when(mockEncryption.keyManager).thenReturn(mockKeyManager);
    when(mockClient.userID).thenReturn('@user:example.com');
    when(mockClient.deviceID).thenReturn('DEVICE_1');
  });

  group('KeyBackupSigner', () {
    test('does not throw on getRoomKeysBackupInfo error', () async {
      when(mockKeyManager.getRoomKeysBackupInfo(any)).thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_NOT_FOUND',
          'error': 'No backup found',
        }),
      );

      await KeyBackupSigner.signWithCrossSigning(
        mockClient,
        mockEncryption,
        mockSsssKey,
      );

      verifyNever(mockClient.putRoomKeysVersion(any, any, any));
    });

    test('does not throw on getStored error', () async {
      when(mockKeyManager.getRoomKeysBackupInfo(any)).thenAnswer(
        (_) async => GetRoomKeysVersionCurrentResponse.fromJson({
          'algorithm': BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2.name,
          'auth_data': <String, dynamic>{'public_key': 'fake'},
          'count': 0,
          'etag': '0',
          'version': '1',
        }),
      );
      final mockOlmManager = MockOlmManager();
      when(mockEncryption.olmManager).thenReturn(mockOlmManager);
      when(mockOlmManager.signString(any)).thenReturn('device_sig');
      when(mockSsssKey.getStored(any))
          .thenThrow(Exception('key not found'));

      await KeyBackupSigner.signWithCrossSigning(
        mockClient,
        mockEncryption,
        mockSsssKey,
      );

      verifyNever(mockClient.putRoomKeysVersion(any, any, any));
    });
  });
}

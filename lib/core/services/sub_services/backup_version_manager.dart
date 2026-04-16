import 'package:flutter/foundation.dart';
import 'package:matrix/encryption/utils/base64_unpadded.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

class BackupVersionManager {
  BackupVersionManager({required Client client}) : _client = client;

  final Client _client;

  Future<GetRoomKeysVersionCurrentResponse?> ensureExists() async {
    final encryption = _client.encryption;
    if (encryption == null) return null;

    try {
      return await encryption.keyManager.getRoomKeysBackupInfo(false);
    } on MatrixException catch (e) {
      if (e.errcode != 'M_NOT_FOUND') return null;
    } catch (_) {
      return null;
    }

    final cachedKey =
        await encryption.ssss.getCached(EventTypes.MegolmBackup);
    if (cachedKey == null) return null;

    debugPrint('[Kohera] Creating backup version from cached megolm key');
    final publicKey = _derivePublicKey(base64decodeUnpadded(cachedKey));

    await _client.postRoomKeysVersion(
      BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2,
      <String, dynamic>{'public_key': publicKey},
    );
    debugPrint('[Kohera] Backup version created on server');

    await _client.database.markInboundGroupSessionsAsNeedingUpload();

    try {
      return await encryption.keyManager.getRoomKeysBackupInfo(false);
    } catch (e) {
      debugPrint('[Kohera] Post-create backup info fetch failed: $e');
      return null;
    }
  }

  Future<bool> cachedSecretMatchesServer() async {
    try {
      final encryption = _client.encryption;
      if (encryption == null) return false;
      final backupInfo =
          await encryption.keyManager.getRoomKeysBackupInfo(false);
      final serverPublicKey =
          backupInfo.authData['public_key'] as String?;
      if (serverPublicKey == null) return false;
      final cachedSecret =
          await encryption.ssss.getCached(EventTypes.MegolmBackup);
      if (cachedSecret == null) return false;
      final derived = _derivePublicKey(base64decodeUnpadded(cachedSecret));
      return derived == serverPublicKey;
    } catch (e) {
      debugPrint('[Kohera] Key match check failed: $e');
      return false;
    }
  }

  String _derivePublicKey(Uint8List privateKey) {
    final decryption = vod.PkDecryption.fromSecretKey(
      vod.Curve25519PublicKey.fromBytes(privateKey),
    );
    return decryption.publicKey;
  }
}

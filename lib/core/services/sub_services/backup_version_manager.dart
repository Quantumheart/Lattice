import 'package:flutter/foundation.dart';
import 'package:matrix/encryption/utils/base64_unpadded.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

class BackupVersionManager {
  BackupVersionManager(this._client);

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
    final privateKey = base64decodeUnpadded(cachedKey);
    final decryption = vod.PkDecryption.fromSecretKey(
      vod.Curve25519PublicKey.fromBytes(privateKey),
    );

    await _client.postRoomKeysVersion(
      BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2,
      <String, dynamic>{'public_key': decryption.publicKey},
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
}

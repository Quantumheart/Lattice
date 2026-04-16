import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/base64_unpadded.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

class KeyBackupSigner {
  static Future<void> signWithCrossSigning(
    Client client,
    Encryption encryption, {
    OpenSSSS? ssssKey,
    GetRoomKeysVersionCurrentResponse? backupInfo,
  }) async {
    try {
      final masterKeySecret = await _readMasterKeySecret(encryption, ssssKey);
      if (masterKeySecret == null) {
        debugPrint(
          '[Bootstrap] No cross-signing master key available to sign backup',
        );
        return;
      }

      final info = backupInfo ??
          await encryption.keyManager.getRoomKeysBackupInfo(false);
      final authData = Map<String, Object?>.from(info.authData);

      final signable = Map<String, Object?>.from(authData);
      signable.remove('signatures');
      signable.remove('unsigned');
      final canonical =
          String.fromCharCodes(canonicalJson.encode(signable));

      final signatures = <String, Map<String, String>>{};
      final existing = authData['signatures'];
      if (existing is Map) {
        for (final entry in existing.entries) {
          if (entry.key is String && entry.value is Map) {
            signatures[entry.key as String] =
                Map<String, String>.from(entry.value as Map);
          }
        }
      }

      final userId = client.userID!;
      final userSigs = signatures[userId] ??= {};

      final deviceSignature = encryption.olmManager.signString(canonical);
      userSigs['ed25519:${client.deviceID}'] = deviceSignature;

      final masterKeyBytes = base64decodeUnpadded(masterKeySecret);
      final masterSigning =
          vod.PkSigning.fromSecretKey(base64Encode(masterKeyBytes));
      final masterPubKey = masterSigning.publicKey.toBase64();
      final masterSignature = masterSigning.sign(canonical).toBase64();
      userSigs['ed25519:$masterPubKey'] = masterSignature;

      authData['signatures'] = signatures;

      await client.putRoomKeysVersion(
        info.version,
        info.algorithm,
        authData,
      );
      debugPrint('[Bootstrap] Key backup signed with master cross-signing key');
    } catch (e) {
      debugPrint('[Bootstrap] Failed to sign key backup: $e');
    }
  }

  static Future<String?> _readMasterKeySecret(
    Encryption encryption,
    OpenSSSS? ssssKey,
  ) async {
    if (ssssKey != null) {
      try {
        return await ssssKey.getStored(EventTypes.CrossSigningMasterKey);
      } catch (e) {
        debugPrint('[Bootstrap] ssssKey.getStored failed: $e');
        return null;
      }
    }
    try {
      return await encryption.ssss.getCached(EventTypes.CrossSigningMasterKey);
    } catch (e) {
      debugPrint('[Bootstrap] ssss.getCached failed: $e');
      return null;
    }
  }
}

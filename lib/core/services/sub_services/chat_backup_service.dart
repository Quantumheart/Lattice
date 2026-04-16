import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/base64_unpadded.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

class ChatBackupService extends ChangeNotifier {
  ChatBackupService({
    required Client client,
    required FlutterSecureStorage storage,
  })  : _client = client,
        _storage = storage;

  final Client _client;
  final FlutterSecureStorage _storage;

  // ── Chat Backup ─────────────────────────────────────────────
  bool? _chatBackupNeeded;
  bool? get chatBackupNeeded => _chatBackupNeeded;
  bool get chatBackupEnabled => _chatBackupNeeded == false;

  bool _chatBackupLoading = false;
  bool get chatBackupLoading => _chatBackupLoading;

  String? _chatBackupError;
  String? get chatBackupError => _chatBackupError;

  Future<void> checkChatBackupStatus() async {
    try {
      await _ensureBackupVersionExists();
      final state = await _client.getCryptoIdentityState();
      debugPrint('[Kohera] Backup status: initialized=${state.initialized}, '
          'connected=${state.connected}');
      _chatBackupNeeded = !state.initialized || !state.connected;
      notifyListeners();
    } catch (e) {
      debugPrint('[Kohera] checkChatBackupStatus error: $e');
      _chatBackupNeeded = true;
      notifyListeners();
    }
  }

  Future<void> disableChatBackup() async {
    _chatBackupError = null;
    _chatBackupLoading = true;
    notifyListeners();

    try {
      final encryption = _client.encryption;
      if (encryption == null) {
        throw Exception('Encryption is not available');
      }
      try {
        final info = await encryption.keyManager.getRoomKeysBackupInfo();
        await _client.deleteRoomKeysVersion(info.version);
      } on MatrixException catch (e) {
        if (e.errcode != 'M_NOT_FOUND') rethrow;
        debugPrint('[Kohera] No server-side key backup to delete');
      }
      await deleteStoredRecoveryKey();
      _chatBackupNeeded = true;
    } catch (e) {
      debugPrint('[Kohera] disableChatBackup error: $e');
      _chatBackupError = 'Failed to disable chat backup. Please try again.';
    } finally {
      _chatBackupLoading = false;
      notifyListeners();
    }
  }

  void resetChatBackupState() {
    _chatBackupNeeded = null;
  }

  // ── Key Restoration ──────────────────────────────────────────

  Future<void> tryAutoUnlockBackup() async {
    final storedKey = await getStoredRecoveryKey();
    if (storedKey != null) {
      debugPrint('[Kohera] Attempting auto-unlock with stored key');

      try {
        final state = await _client.getCryptoIdentityState();
        if (state.connected && await _storedKeyMatchesServer(storedKey)) {
          debugPrint('[Kohera] Skip restore: already connected and key valid');
        } else {
          await _client.restoreCryptoIdentity(storedKey);
        }
        await _restoreRoomKeys();
      } catch (e) {
        debugPrint('[Kohera] Failed: $e');
        await _handleStaleStoredKey();
      }
    } else {
      unawaited(requestMissingRoomKeys());
    }

    await checkChatBackupStatus();
    debugPrint('[Kohera] Complete, chatBackupNeeded=$_chatBackupNeeded');
  }

  Future<bool> _storedKeyMatchesServer(String storedKey) async {
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
      final cachedBytes = base64decodeUnpadded(cachedSecret);
      final decryption = vod.PkDecryption.fromSecretKey(
        vod.Curve25519PublicKey.fromBytes(cachedBytes),
      );
      return decryption.publicKey == serverPublicKey;
    } catch (e) {
      debugPrint('[Kohera] Key match check failed: $e');
      return false;
    }
  }

  Future<void> _handleStaleStoredKey() async {
    debugPrint('[Kohera] Stored recovery key is stale — clearing');
    await deleteStoredRecoveryKey();
    _chatBackupNeeded = true;
    notifyListeners();
  }

  static const int _keyRequestScanLimit = 200;

  Future<void> requestMissingRoomKeys() async {
    final encryption = _client.encryption;
    if (encryption == null) return;

    final seen = <String>{};
    for (final room in _client.rooms) {
      List<Event> events;
      try {
        events = await _client.database
            .getEventList(room, limit: _keyRequestScanLimit);
      } catch (e) {
        debugPrint('[Kohera] getEventList failed for ${room.id}: $e');
        continue;
      }

      for (final event in events) {
        if (event.type != EventTypes.Encrypted ||
            event.messageType != MessageTypes.BadEncrypted ||
            event.content['can_request_session'] != true) {
          continue;
        }
        final sessionId = event.content.tryGet<String>('session_id');
        final senderKey = event.content.tryGet<String>('sender_key');
        if (sessionId == null || senderKey == null) continue;

        final dedupeKey = '${room.id}|$sessionId';
        if (!seen.add(dedupeKey)) continue;

        try {
          encryption.keyManager.maybeAutoRequest(
            room.id,
            sessionId,
            senderKey,
          );
        } catch (e) {
          debugPrint('[Kohera] Key request failed for ${room.id}: $e');
        }
      }
    }
  }

  // ── Recovery Key Storage ──────────────────────────────────────

  Future<String?> getStoredRecoveryKey() async {
    final userId = _client.userID;
    if (userId == null) return null;
    return _storage.read(key: 'ssss_recovery_key_$userId');
  }

  Future<void> storeRecoveryKey(String key) async {
    final userId = _client.userID;
    if (userId == null) return;
    await _storage.write(key: 'ssss_recovery_key_$userId', value: key);
  }

  Future<void> deleteStoredRecoveryKey() async {
    final userId = _client.userID;
    if (userId == null) return;
    await _storage.delete(key: 'ssss_recovery_key_$userId');
  }

  // ── Private ──────────────────────────────────────────────────

  Future<void> _ensureBackupVersionExists() async {
    final encryption = _client.encryption;
    if (encryption == null) return;

    try {
      await encryption.keyManager.getRoomKeysBackupInfo(false);
      return;
    } on MatrixException catch (e) {
      if (e.errcode != 'M_NOT_FOUND') return;
    } catch (_) {
      return;
    }

    final cachedKey =
        await encryption.ssss.getCached(EventTypes.MegolmBackup);
    if (cachedKey == null) return;

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
  }

  Future<void> _restoreRoomKeys() async {
    final encryption = _client.encryption;
    if (encryption == null) return;

    try {
      await encryption.keyManager.loadAllKeys();
      debugPrint('[Kohera] Room keys restored from online backup');
    } catch (e) {
      debugPrint('[Kohera] Failed to load keys from backup: $e');
    }

    await requestMissingRoomKeys();
  }
}

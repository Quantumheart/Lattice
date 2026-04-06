import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/base64_unpadded.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

class ChatBackupService {
  ChatBackupService({
    required Client client,
    required FlutterSecureStorage storage,
    required VoidCallback onChanged,
  })  : _client = client,
        _storage = storage,
        _onChanged = onChanged;

  final Client _client;
  final FlutterSecureStorage _storage;
  final VoidCallback _onChanged;

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
      final state = await _client.getCryptoIdentityState();
      debugPrint('[Lattice] Backup status: initialized=${state.initialized}, '
          'connected=${state.connected}');
      _chatBackupNeeded = !state.initialized || !state.connected;
      _onChanged();
    } catch (e) {
      debugPrint('[Lattice] checkChatBackupStatus error: $e');
      _chatBackupNeeded = true;
      _onChanged();
    }
  }

  // ── Auto-unlock Backup ──────────────────────────────────────

  Future<void> tryAutoUnlockBackup() async {
    await _ensureBackupVersionExists();

    final storedKey = await getStoredRecoveryKey();
    if (storedKey == null) return;

    debugPrint('[Lattice] Attempting auto-unlock with stored key');

    try {
      final state = await _client.getCryptoIdentityState();
      if (state.connected) {
        debugPrint('[Lattice] Skip restore: already connected');
      } else {
        await _client.restoreCryptoIdentity(storedKey);
      }
      await _restoreRoomKeys();
    } catch (e) {
      debugPrint('[Lattice] Failed: $e');
    }

    await checkChatBackupStatus();
    debugPrint('[Lattice] Complete, chatBackupNeeded=$_chatBackupNeeded');
  }

  Future<void> _restoreRoomKeys() async {
    final encryption = _client.encryption;
    if (encryption == null) return;

    try {
      await encryption.keyManager.loadAllKeys();
      debugPrint('[Lattice] Room keys restored from online backup');
    } catch (e) {
      debugPrint('[Lattice] Failed to load keys from backup: $e');
    }

    requestMissingRoomKeys();
  }

  void requestMissingRoomKeys() {
    final encryption = _client.encryption;
    if (encryption == null) return;

    for (final room in _client.rooms) {
      final event = room.lastEvent;
      if (event != null &&
          event.type == EventTypes.Encrypted &&
          event.messageType == MessageTypes.BadEncrypted &&
          event.content['can_request_session'] == true) {
        final sessionId = event.content.tryGet<String>('session_id');
        final senderKey = event.content.tryGet<String>('sender_key');
        if (sessionId != null && senderKey != null) {
          try {
            encryption.keyManager.maybeAutoRequest(
              room.id,
              sessionId,
              senderKey,
            );
          } catch (e) {
            debugPrint('[Lattice] Key request failed for ${room.id}: $e');
          }
        }
      }
    }
  }

  // ── Backup Version ───────────────────────────────────────────

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

    debugPrint('[Lattice] Creating backup version from cached megolm key');
    final privateKey = base64decodeUnpadded(cachedKey);
    final decryption = vod.PkDecryption.fromSecretKey(
      vod.Curve25519PublicKey.fromBytes(privateKey),
    );

    await _client.postRoomKeysVersion(
      BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2,
      <String, dynamic>{'public_key': decryption.publicKey},
    );
    debugPrint('[Lattice] Backup version created on server');

    await _client.database.markInboundGroupSessionsAsNeedingUpload();
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

  Future<void> disableChatBackup() async {
    _chatBackupError = null;
    _chatBackupLoading = true;
    _onChanged();

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
        debugPrint('[Lattice] No server-side key backup to delete');
      }
      await deleteStoredRecoveryKey();
      _chatBackupNeeded = true;
    } catch (e) {
      debugPrint('[Lattice] disableChatBackup error: $e');
      _chatBackupError = 'Failed to disable chat backup. Please try again.';
    } finally {
      _chatBackupLoading = false;
      _onChanged();
    }
  }

  void resetChatBackupState() {
    _chatBackupNeeded = null;
  }
}

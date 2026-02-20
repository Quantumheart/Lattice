import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// E2EE chat-backup status, recovery-key storage, and auto-unlock.
mixin ChatBackupMixin on ChangeNotifier {
  Client get client;
  FlutterSecureStorage get storage;

  // ── Chat Backup ─────────────────────────────────────────────
  /// null = loading/unknown, true = needs setup, false = ok
  bool? _chatBackupNeeded;
  bool? get chatBackupNeeded => _chatBackupNeeded;
  bool get chatBackupEnabled => _chatBackupNeeded == false;

  bool _chatBackupLoading = false;
  bool get chatBackupLoading => _chatBackupLoading;

  String? _chatBackupError;
  String? get chatBackupError => _chatBackupError;

  Future<void> checkChatBackupStatus() async {
    try {
      final state = await client.getCryptoIdentityState();
      debugPrint('[BackupStatus] initialized=${state.initialized}, '
          'connected=${state.connected}');
      _chatBackupNeeded = !state.initialized || !state.connected;
      notifyListeners();
    } catch (e) {
      debugPrint('checkChatBackupStatus error: $e');
      _chatBackupNeeded = true;
      notifyListeners();
    }
  }

  // ── Auto-unlock Backup ──────────────────────────────────────

  /// Attempts to silently unlock the existing backup using a stored recovery
  /// key. Runs a headless bootstrap, auto-advancing all states and unlocking
  /// SSSS when [openExistingSsss] is reached. If no stored key is available
  /// or the key is invalid, this is a no-op.
  @protected
  Future<void> tryAutoUnlockBackup() async {
    final storedKey = await getStoredRecoveryKey();
    if (storedKey == null) return;

    debugPrint('[AutoUnlock] Attempting auto-unlock with stored key');

    try {
      final state = await client.getCryptoIdentityState();
      if (!state.initialized || state.connected) {
        debugPrint('[AutoUnlock] Skip: initialized=${state.initialized}, connected=${state.connected}');
      } else {
        await client.restoreCryptoIdentity(storedKey);
      }
    } catch (e) {
      debugPrint('[AutoUnlock] Failed: $e');
      // Silent failure — user can still unlock manually via settings.
    }

    await checkChatBackupStatus();
    debugPrint('[AutoUnlock] Complete, chatBackupNeeded=$_chatBackupNeeded');
  }

  // ── Recovery Key Storage ──────────────────────────────────────

  Future<String?> getStoredRecoveryKey() async {
    final userId = client.userID;
    if (userId == null) return null;
    return storage.read(key: 'ssss_recovery_key_$userId');
  }

  Future<void> storeRecoveryKey(String key) async {
    final userId = client.userID;
    if (userId == null) return;
    await storage.write(key: 'ssss_recovery_key_$userId', value: key);
  }

  Future<void> deleteStoredRecoveryKey() async {
    final userId = client.userID;
    if (userId == null) return;
    await storage.delete(key: 'ssss_recovery_key_$userId');
  }

  Future<void> disableChatBackup() async {
    _chatBackupError = null;
    _chatBackupLoading = true;
    notifyListeners();

    try {
      final encryption = client.encryption;
      if (encryption == null) {
        throw Exception('Encryption is not available');
      }
      try {
        final info = await encryption.keyManager.getRoomKeysBackupInfo();
        await client.deleteRoomKeysVersion(info.version);
      } on MatrixException catch (e) {
        // M_NOT_FOUND means no backup exists — treat as already disabled.
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
      notifyListeners();
    }
  }

  /// Reset chat backup state (e.g. on logout).
  @protected
  void resetChatBackupState() {
    _chatBackupNeeded = null;
  }
}

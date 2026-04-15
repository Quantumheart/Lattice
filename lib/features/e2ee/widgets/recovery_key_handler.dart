import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/encryption.dart';

class RecoveryKeyHandler {
  RecoveryKeyHandler({required this.matrixService});

  final MatrixService matrixService;

  // ── State ─────────────────────────────────────────────────────

  String? _newRecoveryKey;
  bool _generatingKey = false;
  bool _saveToDevice = false;
  bool _keyCopied = false;
  String? _recoveryKeyError;
  OpenSSSS? _unlockedSsssKey;
  String? _storedRecoveryKey;

  // ── Getters ───────────────────────────────────────────────────

  String? get newRecoveryKey => _newRecoveryKey;
  bool get generatingKey => _generatingKey;
  bool get saveToDevice => _saveToDevice;
  bool get keyCopied => _keyCopied;
  bool get canConfirmNewKey => _keyCopied || _saveToDevice;
  String? get recoveryKeyError => _recoveryKeyError;
  OpenSSSS? get unlockedSsssKey => _unlockedSsssKey;

  // ── Actions ───────────────────────────────────────────────────

  void setSaveToDevice(bool value) {
    _saveToDevice = value;
  }

  void setKeyCopied() {
    _keyCopied = true;
  }

  Future<void> generateNewKey(Bootstrap bootstrap) async {
    _generatingKey = true;
    try {
      await bootstrap.newSsss();
      _newRecoveryKey = bootstrap.newSsssKey?.recoveryKey;
      _generatingKey = false;
    } catch (e) {
      _generatingKey = false;
      rethrow;
    }
  }

  Future<void> loadStoredKey() async {
    final storedKey = await matrixService.chatBackup.getStoredRecoveryKey();
    if (storedKey != null) {
      _storedRecoveryKey = storedKey;
    }
  }

  String? consumeStoredRecoveryKey() {
    final key = _storedRecoveryKey;
    _storedRecoveryKey = null;
    return key;
  }

  Future<bool> unlockExisting(Bootstrap bootstrap, String key) async {
    final ssssKey = bootstrap.newSsssKey;
    if (ssssKey == null) return false;

    if (key.isEmpty) {
      _recoveryKeyError = 'Please enter a recovery key';
      return false;
    }

    try {
      await ssssKey.unlock(keyOrPassphrase: key);
      _unlockedSsssKey = ssssKey;
    } catch (e) {
      _recoveryKeyError = 'Invalid recovery key';
      return false;
    }

    _recoveryKeyError = null;
    if (_saveToDevice) {
      await matrixService.chatBackup.storeRecoveryKey(key);
    }

    try {
      await bootstrap.openExistingSsss();
      final encryption = matrixService.client.encryption;
      if (encryption != null && encryption.crossSigning.enabled) {
        debugPrint('[Bootstrap] Self-signing after SSSS unlock');
        await encryption.crossSigning.selfSign(recoveryKey: key);
      }
    } catch (e) {
      _recoveryKeyError = 'Failed to open backup: $e';
      return false;
    }

    return true;
  }

  Future<void> storeIfNeeded() async {
    if (_saveToDevice && _newRecoveryKey != null) {
      await matrixService.chatBackup.storeRecoveryKey(_newRecoveryKey!);
    }
  }

  void reset() {
    _newRecoveryKey = null;
    _generatingKey = false;
    _keyCopied = false;
    _recoveryKeyError = null;
    _unlockedSsssKey = null;
    _storedRecoveryKey = null;
  }

  void dispose() {
    _newRecoveryKey = null;
    _storedRecoveryKey = null;
    _unlockedSsssKey = null;
  }
}

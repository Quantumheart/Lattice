import 'dart:async';
import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/base64_unpadded.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import '../services/matrix_service.dart';

/// Signals for UI-only actions that the dialog must handle.
enum BootstrapAction {
  none,
  startVerification,
  confirmLostKey,
  confirmCancel,
  done,
}

/// Extracted business logic for the bootstrap flow.
///
/// All state and state-machine logic lives here; the dialog is a thin shell
/// that listens to [notifyListeners] and reads the public getters.
class BootstrapController extends ChangeNotifier {
  BootstrapController({
    required this.matrixService,
    required bool wipeExisting,
  }) : _wipeExisting = wipeExisting;

  final MatrixService matrixService;

  // ── State fields ──────────────────────────────────────────────

  Bootstrap? _bootstrap;
  BootstrapState _state = BootstrapState.loading;
  String? _error;
  bool _wipeExisting;

  String? _newRecoveryKey;
  bool _generatingKey = false;
  bool _awaitingKeyAck = false;
  bool _saveToDevice = false;
  bool _keyCopied = false;
  bool _verifying = false;
  String? _recoveryKeyError;
  OpenSSSS? _unlockedSsssKey;
  StreamSubscription? _secretStoredSub;

  bool _isDisposed = false;

  // ── Public getters ────────────────────────────────────────────

  Bootstrap? get bootstrap => _bootstrap;
  BootstrapState get state => _state;
  String? get error => _error;
  String? get newRecoveryKey => _newRecoveryKey;
  bool get generatingKey => _generatingKey;
  bool get saveToDevice => _saveToDevice;
  bool get keyCopied => _keyCopied;
  bool get canConfirmNewKey => _keyCopied || _saveToDevice;
  bool get verifying => _verifying;
  String? get recoveryKeyError => _recoveryKeyError;

  /// When non-null the dialog should wrap this in addPostFrameCallback.
  VoidCallback? deferredAdvance;

  /// Signals UI-only work (show nested dialog, pop, etc.).
  BootstrapAction pendingAction = BootstrapAction.none;

  /// Clears the pending action after the dialog has handled it.
  void clearPendingAction() {
    pendingAction = BootstrapAction.none;
  }

  // ── Title helper ──────────────────────────────────────────────

  String get title {
    switch (_state) {
      case BootstrapState.loading:
      case BootstrapState.askWipeSsss:
      case BootstrapState.askWipeCrossSigning:
      case BootstrapState.askSetupCrossSigning:
      case BootstrapState.askWipeOnlineKeyBackup:
      case BootstrapState.askSetupOnlineKeyBackup:
      case BootstrapState.askBadSsss:
        return 'Setting up backup';
      case BootstrapState.askNewSsss:
        return 'Save your recovery key';
      case BootstrapState.openExistingSsss:
        return 'Enter recovery key';
      case BootstrapState.askUseExistingSsss:
      case BootstrapState.askUnlockSsss:
        return 'Setting up backup';
      case BootstrapState.done:
        return 'Backup complete';
      case BootstrapState.error:
        return 'Backup error';
    }
  }

  // ── Bootstrap lifecycle ───────────────────────────────────────

  Future<void> startBootstrap() async {
    final client = matrixService.client;
    final encryption = client.encryption;
    if (encryption == null) {
      _state = BootstrapState.error;
      _error = 'Encryption is not available';
      _notify();
      return;
    }

    try {
      const syncTimeout = Duration(seconds: 30);
      debugPrint('[Bootstrap] Waiting for roomsLoading...');
      await client.roomsLoading;
      debugPrint('[Bootstrap] Waiting for accountDataLoading...');
      await client.accountDataLoading;
      debugPrint('[Bootstrap] Waiting for userDeviceKeysLoading...');
      await client.userDeviceKeysLoading;
      debugPrint('[Bootstrap] prevBatch=${client.prevBatch}');
      if (client.prevBatch == null) {
        debugPrint('[Bootstrap] Waiting for first sync...');
        await client.onSync.stream.first.timeout(syncTimeout);
      }
      debugPrint('[Bootstrap] Updating user device keys...');
      await client.updateUserDeviceKeys();
      debugPrint('[Bootstrap] Sync preparation complete');
    } on TimeoutException {
      debugPrint('[Bootstrap] Timed out waiting for first sync');
      if (_isDisposed) return;
      _state = BootstrapState.error;
      _error = 'Timed out waiting for sync. Check your connection and retry.';
      _notify();
      return;
    } catch (e, s) {
      debugPrint('[Bootstrap] Sync preparation failed: $e\n$s');
      if (_isDisposed) return;
      _state = BootstrapState.error;
      _error = 'Failed to sync before bootstrap: $e';
      _notify();
      return;
    }

    if (_isDisposed) return;

    debugPrint('[Bootstrap] Starting bootstrap...');
    _bootstrap = encryption.bootstrap(onUpdate: _onBootstrapUpdate);
  }

  void _onBootstrapUpdate(Bootstrap bootstrap) {
    debugPrint('[Bootstrap] onUpdate: state=${bootstrap.state}, disposed=$_isDisposed');
    if (_isDisposed) return;

    _bootstrap = bootstrap;
    final state = bootstrap.state;

    // Auto-advance states that don't need user interaction.
    switch (state) {
      case BootstrapState.askWipeSsss:
        debugPrint('[Bootstrap] Auto-advancing: wipeSsss($_wipeExisting)');
        deferredAdvance = () => bootstrap.wipeSsss(_wipeExisting);
        _notify();
        return;
      case BootstrapState.askWipeCrossSigning:
        debugPrint('[Bootstrap] Auto-advancing: wipeCrossSigning($_wipeExisting)');
        deferredAdvance = () => bootstrap.wipeCrossSigning(_wipeExisting);
        _notify();
        return;
      case BootstrapState.askSetupCrossSigning:
        debugPrint('[Bootstrap] Auto-advancing: askSetupCrossSigning');
        deferredAdvance = () => bootstrap.askSetupCrossSigning(
              setupMasterKey: true,
              setupSelfSigningKey: true,
              setupUserSigningKey: true,
            );
        _notify();
        return;
      case BootstrapState.askWipeOnlineKeyBackup:
        deferredAdvance = () async {
          // Check if a backup version actually exists on the server.
          // If it was deleted (e.g. via disableChatBackup), pass true
          // to trigger askSetupOnlineKeyBackup and create a new one.
          var wipe = _wipeExisting;
          if (!wipe) {
            try {
              await matrixService.client.encryption?.keyManager
                  .getRoomKeysBackupInfo(false);
            } on MatrixException catch (e) {
              if (e.errcode == 'M_NOT_FOUND') {
                debugPrint('[Bootstrap] No server-side backup found, '
                    'triggering creation');
                wipe = true;
              }
            } catch (_) {}
          }
          debugPrint('[Bootstrap] Auto-advancing: wipeOnlineKeyBackup($wipe)');
          bootstrap.wipeOnlineKeyBackup(wipe);
        };
        _notify();
        return;
      case BootstrapState.askSetupOnlineKeyBackup:
        debugPrint('[Bootstrap] Auto-advancing: askSetupOnlineKeyBackup');
        deferredAdvance = () => bootstrap.askSetupOnlineKeyBackup(true);
        _notify();
        return;
      case BootstrapState.askBadSsss:
        debugPrint('[Bootstrap] Auto-advancing: ignoreBadSecrets');
        deferredAdvance = () => bootstrap.ignoreBadSecrets(true);
        _notify();
        return;
      case BootstrapState.askUseExistingSsss:
        debugPrint('[Bootstrap] Auto-advancing: useExistingSsss(${!_wipeExisting})');
        deferredAdvance = () => bootstrap.useExistingSsss(!_wipeExisting);
        _notify();
        return;
      case BootstrapState.askUnlockSsss:
        debugPrint('[Bootstrap] Auto-advancing: unlockedSsss');
        deferredAdvance = () => bootstrap.unlockedSsss();
        _notify();
        return;
      default:
        break;
    }

    // If we're awaiting user acknowledgement of the recovery key,
    // don't let the bootstrap auto-advance the UI state.
    if (_awaitingKeyAck && state != BootstrapState.error) {
      return;
    }

    _state = state;
    if (state == BootstrapState.askNewSsss) {
      _generateNewSsssKey();
    }
    if (state == BootstrapState.openExistingSsss) {
      _loadStoredRecoveryKey();
    }
    _notify();
  }

  // ── Key generation ────────────────────────────────────────────

  Future<void> _generateNewSsssKey() async {
    _generatingKey = true;
    _notify();
    try {
      final bootstrap = _bootstrap;
      if (bootstrap == null) return;
      _awaitingKeyAck = true;
      await bootstrap.newSsss();
      if (_isDisposed) return;
      _newRecoveryKey = bootstrap.newSsssKey?.recoveryKey;
      _generatingKey = false;
      _notify();
    } catch (e) {
      if (_isDisposed) return;
      _generatingKey = false;
      _state = BootstrapState.error;
      _error = 'Failed to generate recovery key: $e';
      _notify();
    }
  }

  Future<void> _loadStoredRecoveryKey() async {
    final storedKey = await matrixService.getStoredRecoveryKey();
    if (storedKey != null && !_isDisposed) {
      _storedRecoveryKey = storedKey;
      _notify();
    }
  }

  /// Set by _loadStoredRecoveryKey; the dialog should apply this to the
  /// TextEditingController.
  String? _storedRecoveryKey;
  String? consumeStoredRecoveryKey() {
    final key = _storedRecoveryKey;
    _storedRecoveryKey = null;
    return key;
  }

  // ── User actions ──────────────────────────────────────────────

  void setSaveToDevice(bool value) {
    _saveToDevice = value;
    _notify();
  }

  void setKeyCopied() {
    _keyCopied = true;
    _notify();
  }

  // useExistingSsss and skipOldSsssUnlock removed — now auto-advanced.

  void confirmNewSsss() {
    _awaitingKeyAck = false;
    if (_bootstrap != null) {
      _onBootstrapUpdate(_bootstrap!);
    }
  }

  Future<void> unlockExistingSsss(String key) async {
    final bootstrap = _bootstrap;
    final ssssKey = bootstrap?.newSsssKey;
    if (ssssKey == null) return;

    if (key.isEmpty) {
      _recoveryKeyError = 'Please enter a recovery key';
      _notify();
      return;
    }

    try {
      await ssssKey.unlock(keyOrPassphrase: key);
      _unlockedSsssKey = ssssKey;
    } catch (e) {
      _recoveryKeyError = 'Invalid recovery key';
      _notify();
      return;
    }

    _recoveryKeyError = null;
    if (_saveToDevice) {
      await matrixService.storeRecoveryKey(key);
    }

    try {
      await bootstrap!.openExistingSsss();
      // Self-sign immediately after unlocking, matching FluffyChat behavior.
      final encryption = matrixService.client.encryption;
      if (encryption != null && encryption.crossSigning.enabled) {
        debugPrint('[Bootstrap] Self-signing after SSSS unlock');
        await encryption.crossSigning.selfSign(recoveryKey: key);
      }
    } catch (e) {
      _state = BootstrapState.error;
      _error = 'Failed to open backup: $e';
      _notify();
    }
  }


  void requestVerification() {
    pendingAction = BootstrapAction.startVerification;
    _notify();
  }

  void requestCancel() {
    pendingAction = BootstrapAction.confirmCancel;
    _notify();
  }

  void requestLostKeyConfirmation() {
    pendingAction = BootstrapAction.confirmLostKey;
    _notify();
  }

  void setVerifying(bool value) {
    _verifying = value;
    _notify();
  }

  /// Called by the dialog after a successful device verification to try
  /// continuing the bootstrap with the now-cached secrets.
  void onSecretStoredSub(StreamSubscription sub) {
    _secretStoredSub = sub;
  }

  void cancelSecretStoredSub() {
    _secretStoredSub?.cancel();
    _secretStoredSub = null;
  }

  void retry() {
    _resetState();
    startBootstrap();
  }

  void restartWithWipe() {
    _wipeExisting = true;
    _resetState();
    startBootstrap();
  }

  void _resetState() {
    _state = BootstrapState.loading;
    _error = null;
    _newRecoveryKey = null;
    _generatingKey = false;
    _awaitingKeyAck = false;
    _keyCopied = false;
    _recoveryKeyError = null;
    _unlockedSsssKey = null;
    _notify();
  }

  Future<void> onDone() async {
    if (_saveToDevice && _newRecoveryKey != null) {
      await matrixService.storeRecoveryKey(_newRecoveryKey!);
    }

    // The bootstrap stored secrets in SSSS on the server but the local
    // cache may not reflect them yet. Explicitly cache and self-sign so
    // that checkChatBackupStatus sees the correct state.
    // Prefer the key we unlocked in unlockExistingSsss (which may differ
    // from the bootstrap's current newSsssKey after state transitions).
    final client = matrixService.client;
    final encryption = client.encryption;
    final ssssKey = _unlockedSsssKey ?? _bootstrap?.newSsssKey;
    if (encryption != null && ssssKey != null && ssssKey.isUnlocked) {
      try {
        await ssssKey.maybeCacheAll();
        if (encryption.crossSigning.enabled) {
          await encryption.crossSigning.selfSign(openSsss: ssssKey);
        }
      } catch (e) {
        debugPrint('[Bootstrap] Post-bootstrap caching/signing failed: $e');
      }
      await client.updateUserDeviceKeys();

      // The SDK does not sign the key backup auth_data with the master
      // cross-signing key. Other clients (Element, etc.) require this
      // signature to trust the backup. Sign it now while we have access
      // to the SSSS secrets.
      await _signKeyBackupWithCrossSigning(client, encryption, ssssKey);
    }

    // Restore room keys from the online key backup.
    try {
      await encryption?.keyManager.loadAllKeys();
      debugPrint('[Bootstrap] Room keys restored from online backup');
    } catch (e) {
      debugPrint('[Bootstrap] Failed to load keys from backup: $e');
      // Fall back to requesting keys from other devices.
      _requestMissingKeys();
    }

    await matrixService.checkChatBackupStatus();
    matrixService.clearCachedPassword();
    pendingAction = BootstrapAction.done;
    _notify();
  }

  // ── Key backup signing ───────────────────────────────────────

  /// Signs the key backup's auth_data with both the device key and the
  /// master cross-signing key so that other clients trust the backup.
  Future<void> _signKeyBackupWithCrossSigning(
    Client client,
    Encryption encryption,
    OpenSSSS ssssKey,
  ) async {
    try {
      // Bust the cache — the bootstrap may have deleted the old backup and
      // created a new one, leaving the KeyManager cache stale.
      final backupInfo =
          await encryption.keyManager.getRoomKeysBackupInfo(false);
      final authData = Map<String, Object?>.from(backupInfo.authData);

      // Strip signatures/unsigned for canonical JSON signing.
      final signable = Map<String, Object?>.from(authData);
      signable.remove('signatures');
      signable.remove('unsigned');
      final canonical =
          String.fromCharCodes(canonicalJson.encode(signable));

      // Collect existing signatures (if any).
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

      // Sign with device key.
      final deviceSignature = encryption.olmManager.signString(canonical);
      userSigs['ed25519:${client.deviceID}'] = deviceSignature;

      // Sign with master cross-signing key.
      final masterKeySecret =
          await ssssKey.getStored(EventTypes.CrossSigningMasterKey);
      final masterKeyBytes = base64decodeUnpadded(masterKeySecret);
      final masterSigning =
          vod.PkSigning.fromSecretKey(base64Encode(masterKeyBytes));
      final masterPubKey = masterSigning.publicKey.toBase64();
      final masterSignature = masterSigning.sign(canonical).toBase64();
      userSigs['ed25519:$masterPubKey'] = masterSignature;

      authData['signatures'] = signatures;

      await client.putRoomKeysVersion(
        backupInfo.version,
        backupInfo.algorithm,
        authData,
      );
      debugPrint('[Bootstrap] Key backup signed with master cross-signing key');
    } catch (e) {
      debugPrint('[Bootstrap] Failed to sign key backup: $e');
      // Non-fatal — backup still works, just won't show as trusted
      // in other clients until they verify this device.
    }
  }

  // ── Internals ─────────────────────────────────────────────────

  void _requestMissingKeys() {
    final client = matrixService.client;
    for (final room in client.rooms) {
      final event = room.lastEvent;
      if (event != null &&
          event.type == EventTypes.Encrypted &&
          event.messageType == MessageTypes.BadEncrypted &&
          event.content['can_request_session'] == true) {
        final sessionId = event.content.tryGet<String>('session_id');
        final senderKey = event.content.tryGet<String>('sender_key');
        if (sessionId != null && senderKey != null) {
          client.encryption?.keyManager.maybeAutoRequest(
            room.id,
            sessionId,
            senderKey,
          );
        }
      }
    }
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _newRecoveryKey = null;
    _storedRecoveryKey = null;
    _unlockedSsssKey = null;
    _secretStoredSub?.cancel();
    super.dispose();
  }
}

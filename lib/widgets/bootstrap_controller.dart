import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';

import '../services/matrix_service.dart';

/// Signals for UI-only actions that the dialog must handle.
enum BootstrapAction {
  none,
  startVerification,
  confirmLostKey,
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
  bool _verifying = false;
  String? _recoveryKeyError;
  StreamSubscription? _secretStoredSub;

  bool _isDisposed = false;

  // ── Public getters ────────────────────────────────────────────

  Bootstrap? get bootstrap => _bootstrap;
  BootstrapState get state => _state;
  String? get error => _error;
  String? get newRecoveryKey => _newRecoveryKey;
  bool get generatingKey => _generatingKey;
  bool get saveToDevice => _saveToDevice;
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
        return 'Existing backup found';
      case BootstrapState.askUnlockSsss:
        return 'Unlock backup';
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
      debugPrint('[Bootstrap] Waiting for roomsLoading...');
      await client.roomsLoading;
      debugPrint('[Bootstrap] Waiting for accountDataLoading...');
      await client.accountDataLoading;
      debugPrint('[Bootstrap] Waiting for userDeviceKeysLoading...');
      await client.userDeviceKeysLoading;
      debugPrint('[Bootstrap] prevBatch=${client.prevBatch}');
      while (client.prevBatch == null) {
        debugPrint('[Bootstrap] Waiting for first sync...');
        await client.onSync.stream.first;
      }
      debugPrint('[Bootstrap] Updating user device keys...');
      await client.updateUserDeviceKeys();
      debugPrint('[Bootstrap] Sync preparation complete');
    } catch (e, s) {
      debugPrint('[Bootstrap] Sync preparation failed: $e\n$s');
      if (_isDisposed) return;
      _state = BootstrapState.error;
      _error = 'Failed to sync before bootstrap: $e';
      _notify();
      return;
    }

    if (_isDisposed) return;

    // Workaround for SDK bug: OpenSSSS.store() crashes with a null check
    // on accountData[type].content['encrypted'] when stale entries exist
    // without the 'encrypted' field (ssss.dart:793).
    client.accountData.removeWhere((type, event) {
      if (!event.content.containsKey('encrypted')) return false;
      return event.content['encrypted'] is! Map;
    });

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
        debugPrint('[Bootstrap] Auto-advancing: wipeOnlineKeyBackup($_wipeExisting)');
        deferredAdvance = () => bootstrap.wipeOnlineKeyBackup(_wipeExisting);
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

  void useExistingSsss(bool use) {
    _bootstrap?.useExistingSsss(use);
  }

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
    } catch (e) {
      _state = BootstrapState.error;
      _error = 'Failed to open backup: $e';
      _notify();
    }
  }

  Future<void> unlockOldSsss(String key) async {
    final bootstrap = _bootstrap;
    if (bootstrap == null) return;

    if (key.isEmpty) {
      _recoveryKeyError = 'Please enter a recovery key';
      _notify();
      return;
    }

    try {
      final oldKeys = bootstrap.oldSsssKeys;
      if (oldKeys != null) {
        for (final ssssKey in oldKeys.values) {
          await ssssKey.unlock(keyOrPassphrase: key);
        }
      }
      _recoveryKeyError = null;
      bootstrap.unlockedSsss();
      _notify();
    } catch (e) {
      _recoveryKeyError = 'Invalid recovery key';
      _notify();
    }
  }

  void requestVerification() {
    pendingAction = BootstrapAction.startVerification;
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

  void restartWithWipe() {
    _wipeExisting = true;
    _state = BootstrapState.loading;
    _error = null;
    _newRecoveryKey = null;
    _generatingKey = false;
    _awaitingKeyAck = false;
    _recoveryKeyError = null;
    _notify();
    startBootstrap();
  }

  Future<void> onDone() async {
    if (_saveToDevice && _newRecoveryKey != null) {
      await matrixService.storeRecoveryKey(_newRecoveryKey!);
    }
    await matrixService.checkChatBackupStatus();
    pendingAction = BootstrapAction.done;
    _notify();
  }

  // ── Internals ─────────────────────────────────────────────────

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _secretStoredSub?.cancel();
    super.dispose();
  }
}

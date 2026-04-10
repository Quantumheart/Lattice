import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/e2ee/widgets/bootstrap_driver.dart';
import 'package:lattice/features/e2ee/widgets/key_backup_signer.dart';
import 'package:lattice/features/e2ee/widgets/recovery_key_handler.dart';
import 'package:matrix/encryption.dart';

enum SetupPhase { loading, savingKey, unlock, verification, done, error }

class BootstrapController extends ChangeNotifier {
  BootstrapController({
    required this.matrixService,
    required bool wipeExisting,
  }) : _keyHandler = RecoveryKeyHandler(matrixService: matrixService) {
    _driver = BootstrapDriver(
      matrixService: matrixService,
      wipeExisting: wipeExisting,
      onPhaseChanged: _onPhaseChanged,
      onNewSsss: _onNewSsss,
      onOpenExistingSsss: _onOpenExistingSsss,
      onDone: _onDone,
      onError: _onError,
    );
  }

  final MatrixService matrixService;
  final RecoveryKeyHandler _keyHandler;
  late final BootstrapDriver _driver;

  // ── State ─────────────────────────────────────────────────────

  SetupPhase _phase = SetupPhase.loading;
  String? _error;
  bool _isDisposed = false;
  bool _onDoneRunning = false;
  KeyVerification? _verification;

  // ── Public getters ────────────────────────────────────────────

  SetupPhase get phase => _phase;
  String? get error => _error;
  String? get newRecoveryKey => _keyHandler.newRecoveryKey;
  bool get generatingKey => _keyHandler.generatingKey;
  bool get saveToDevice => _keyHandler.saveToDevice;
  bool get keyCopied => _keyHandler.keyCopied;
  bool get canConfirmNewKey => _keyHandler.canConfirmNewKey;
  String? get recoveryKeyError => _keyHandler.recoveryKeyError;
  KeyVerification? get verification => _verification;
  String get loadingMessage => _driver.loadingMessage;

  String? consumeStoredRecoveryKey() => _keyHandler.consumeStoredRecoveryKey();

  // ── Bootstrap lifecycle (delegated to driver) ─────────────────

  Future<void> startBootstrap() => _driver.start();

  void confirmNewSsss() => _driver.confirmNewSsss();

  void retry() {
    _error = null;
    _onDoneRunning = false;
    _keyHandler.reset();
    _phase = SetupPhase.loading;
    _notify();
    _driver.restart();
  }

  void restartWithWipe() {
    _error = null;
    _onDoneRunning = false;
    _keyHandler.reset();
    _phase = SetupPhase.loading;
    _notify();
    _driver.restart(wipe: true);
  }

  // ── Driver callbacks ──────────────────────────────────────────

  void _onPhaseChanged(SetupPhase phase) {
    _phase = phase;
    _notify();
  }

  void _onNewSsss() {
    unawaited(_generateNewSsssKey());
  }

  void _onOpenExistingSsss() {
    unawaited(_keyHandler.loadStoredKey().then((_) => _notify()));
  }

  void _onError(String error) {
    _phase = SetupPhase.error;
    _error = error;
    _notify();
  }

  // ── Key generation ────────────────────────────────────────────

  Future<void> _generateNewSsssKey() async {
    _notify();
    try {
      final bootstrap = _driver.bootstrap;
      if (bootstrap == null) return;
      await _keyHandler.generateNewKey(bootstrap);
      if (_isDisposed) return;
      _notify();
    } catch (e) {
      if (_isDisposed) return;
      _onError('Failed to generate recovery key: $e');
    }
  }

  // ── User actions ──────────────────────────────────────────────

  void setSaveToDevice(bool value) {
    _keyHandler.setSaveToDevice(value);
    _notify();
  }

  void setKeyCopied() {
    _keyHandler.setKeyCopied();
    _notify();
  }

  Future<void> unlockExistingSsss(String key) async {
    final bootstrap = _driver.bootstrap;
    if (bootstrap == null) return;

    final success = await _keyHandler.unlockExisting(bootstrap, key);
    if (!success && _keyHandler.recoveryKeyError != null &&
        _keyHandler.recoveryKeyError!.startsWith('Failed to open')) {
      _phase = SetupPhase.error;
      _error = _keyHandler.recoveryKeyError;
    }
    _notify();
  }

  // ── Verification ─────────────────────────────────────────────

  Future<void> startVerification() async {
    final client = matrixService.client;
    final encryption = client.encryption;
    if (encryption == null) return;

    _phase = SetupPhase.verification;
    _notify();

    await client.updateUserDeviceKeys();

    _verification = KeyVerification(
      encryption: encryption,
      userId: client.userID!,
      deviceId: '*',
    );
    await _verification!.start();
    encryption.keyVerificationManager.addRequest(_verification!);
    _notify();
  }

  Future<void> onVerificationDone(bool success) async {
    if (!success) {
      _verification = null;
      _phase = SetupPhase.unlock;
      _notify();
      return;
    }

    _phase = SetupPhase.loading;
    _notify();

    final encryption = matrixService.client.encryption;
    if (encryption != null) {
      for (var i = 0; i < 10; i++) {
        if (_isDisposed) return;
        final cached = await encryption.keyManager.isCached() &&
            await encryption.crossSigning.isCached();
        if (cached) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    if (_isDisposed) return;
    _verification = null;
    await _onDone();
  }

  void onVerificationCancel() {
    _verification = null;
    _phase = SetupPhase.unlock;
    _notify();
  }

  // ── Post-bootstrap finalization ──────────────────────────────

  Future<void> _onDone() async {
    if (_onDoneRunning) return;
    _onDoneRunning = true;

    await _keyHandler.storeIfNeeded();

    final client = matrixService.client;
    final encryption = client.encryption;
    final ssssKey =
        _keyHandler.unlockedSsssKey ?? _driver.bootstrap?.newSsssKey;

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
      await KeyBackupSigner.signWithCrossSigning(client, encryption, ssssKey);
    } else if (encryption != null) {
      try {
        if (encryption.crossSigning.enabled &&
            await encryption.crossSigning.isCached()) {
          debugPrint('[Bootstrap] Self-signing with cached cross-signing keys');
          await encryption.crossSigning.selfSign();
        }
        await client.updateUserDeviceKeys();
      } catch (e) {
        debugPrint('[Bootstrap] Post-verification signing failed: $e');
      }
    }

    if (_driver.bootstrap?.newSsssKey != null) {
      try {
        await client.database.markInboundGroupSessionsAsNeedingUpload();
        debugPrint('[Bootstrap] Marked all local sessions for backup upload');
      } catch (e) {
        debugPrint('[Bootstrap] Failed to mark sessions for upload: $e');
      }
    }

    try {
      await encryption?.keyManager.loadAllKeys();
      debugPrint('[Bootstrap] Room keys restored from online backup');
    } catch (e) {
      debugPrint('[Bootstrap] Failed to load keys from backup: $e');
    }

    matrixService.chatBackup.requestMissingRoomKeys();
    await matrixService.chatBackup.checkChatBackupStatus();
    matrixService.uia.clearCachedPassword();

    _phase = SetupPhase.done;
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
    _driver.dispose();
    _keyHandler.dispose();
    _verification?.onUpdate = null;
    super.dispose();
  }
}

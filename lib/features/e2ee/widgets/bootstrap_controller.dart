import 'dart:async';
import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';
import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/base64_unpadded.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

enum SetupPhase { loading, savingKey, unlock, verification, done, error }

class BootstrapController extends ChangeNotifier {
  BootstrapController({
    required this.matrixService,
    required bool wipeExisting,
  }) : _wipeExisting = wipeExisting;

  final MatrixService matrixService;

  // ── State fields ──────────────────────────────────────────────

  Bootstrap? _bootstrap;
  BootstrapState _state = BootstrapState.loading;
  SetupPhase _phase = SetupPhase.loading;
  String? _error;
  bool _wipeExisting;

  String? _newRecoveryKey;
  bool _generatingKey = false;
  bool _awaitingKeyAck = false;
  bool _saveToDevice = false;
  bool _keyCopied = false;
  String? _recoveryKeyError;
  OpenSSSS? _unlockedSsssKey;
  bool _isDisposed = false;
  bool _onDoneRunning = false;
  KeyVerification? _verification;

  // ── Public getters ────────────────────────────────────────────

  SetupPhase get phase => _phase;
  String? get error => _error;
  String? get newRecoveryKey => _newRecoveryKey;
  bool get generatingKey => _generatingKey;
  bool get saveToDevice => _saveToDevice;
  bool get keyCopied => _keyCopied;
  bool get canConfirmNewKey => _keyCopied || _saveToDevice;
  String? get recoveryKeyError => _recoveryKeyError;
  KeyVerification? get verification => _verification;

  String get loadingMessage => switch (_state) {
        BootstrapState.askSetupCrossSigning => 'Setting up cross-signing...',
        BootstrapState.askSetupOnlineKeyBackup => 'Setting up key backup...',
        _ => 'Preparing...',
      };

  // ── Bootstrap lifecycle ───────────────────────────────────────

  Future<void> startBootstrap() async {
    final client = matrixService.client;
    final encryption = client.encryption;
    if (encryption == null) {
      _state = BootstrapState.error;
      _phase = SetupPhase.error;
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
      _phase = SetupPhase.error;
      _error = 'Timed out waiting for sync. Check your connection and retry.';
      _notify();
      return;
    } catch (e, s) {
      debugPrint('[Bootstrap] Sync preparation failed: $e\n$s');
      if (_isDisposed) return;
      _state = BootstrapState.error;
      _phase = SetupPhase.error;
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
    _state = bootstrap.state;

    switch (_state) {
      case BootstrapState.askWipeSsss:
        debugPrint('[Bootstrap] Auto-advancing: wipeSsss($_wipeExisting)');
        _advance(() => bootstrap.wipeSsss(_wipeExisting));
        return;
      case BootstrapState.askWipeCrossSigning:
        debugPrint('[Bootstrap] Auto-advancing: wipeCrossSigning($_wipeExisting)');
        _advance(() => bootstrap.wipeCrossSigning(_wipeExisting));
        return;
      case BootstrapState.askSetupCrossSigning:
        debugPrint('[Bootstrap] Auto-advancing: askSetupCrossSigning');
        _advance(
          () => bootstrap.askSetupCrossSigning(
            setupMasterKey: true,
            setupSelfSigningKey: true,
            setupUserSigningKey: true,
          ),
        );
        _notify();
        return;
      case BootstrapState.askWipeOnlineKeyBackup:
        _advance(() async {
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
        });
        return;
      case BootstrapState.askSetupOnlineKeyBackup:
        debugPrint('[Bootstrap] Auto-advancing: askSetupOnlineKeyBackup');
        _advance(() => bootstrap.askSetupOnlineKeyBackup(true));
        _notify();
        return;
      case BootstrapState.askBadSsss:
        debugPrint('[Bootstrap] Auto-advancing: ignoreBadSecrets');
        _advance(() => bootstrap.ignoreBadSecrets(true));
        return;
      case BootstrapState.askUseExistingSsss:
        debugPrint('[Bootstrap] Auto-advancing: useExistingSsss(${!_wipeExisting})');
        _advance(() => bootstrap.useExistingSsss(!_wipeExisting));
        return;
      case BootstrapState.askUnlockSsss:
        debugPrint('[Bootstrap] Auto-advancing: unlockedSsss');
        _advance(() => bootstrap.unlockedSsss());
        return;
      case BootstrapState.done:
        unawaited(_onDone());
        return;
      default:
        break;
    }

    if (_awaitingKeyAck && _state != BootstrapState.error) {
      return;
    }

    _phase = _phaseFromState(_state);
    if (_state == BootstrapState.askNewSsss) {
      unawaited(_generateNewSsssKey());
    }
    if (_state == BootstrapState.openExistingSsss) {
      unawaited(_loadStoredRecoveryKey());
    }
    _notify();
  }

  static SetupPhase _phaseFromState(BootstrapState state) => switch (state) {
        BootstrapState.askNewSsss => SetupPhase.savingKey,
        BootstrapState.openExistingSsss => SetupPhase.unlock,
        BootstrapState.error => SetupPhase.error,
        _ => SetupPhase.loading,
      };

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
      _phase = SetupPhase.error;
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
      final encryption = matrixService.client.encryption;
      if (encryption != null && encryption.crossSigning.enabled) {
        debugPrint('[Bootstrap] Self-signing after SSSS unlock');
        await encryption.crossSigning.selfSign(recoveryKey: key);
      }
    } catch (e) {
      _phase = SetupPhase.error;
      _error = 'Failed to open backup: $e';
      _notify();
    }
  }

  void retry() {
    _resetState();
    unawaited(startBootstrap());
  }

  void restartWithWipe() {
    _wipeExisting = true;
    _resetState();
    unawaited(startBootstrap());
  }

  void _resetState() {
    _state = BootstrapState.loading;
    _phase = SetupPhase.loading;
    _error = null;
    _newRecoveryKey = null;
    _generatingKey = false;
    _awaitingKeyAck = false;
    _keyCopied = false;
    _recoveryKeyError = null;
    _unlockedSsssKey = null;
    _onDoneRunning = false;
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

    if (_saveToDevice && _newRecoveryKey != null) {
      await matrixService.storeRecoveryKey(_newRecoveryKey!);
    }

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
      await _signKeyBackupWithCrossSigning(client, encryption, ssssKey);
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

    try {
      await encryption?.keyManager.loadAllKeys();
      debugPrint('[Bootstrap] Room keys restored from online backup');
    } catch (e) {
      debugPrint('[Bootstrap] Failed to load keys from backup: $e');
    }

    matrixService.requestMissingRoomKeys();
    await matrixService.checkChatBackupStatus();
    matrixService.clearCachedPassword();

    _phase = SetupPhase.done;
    _notify();
  }

  // ── Key backup signing ───────────────────────────────────────

  Future<void> _signKeyBackupWithCrossSigning(
    Client client,
    Encryption encryption,
    OpenSSSS ssssKey,
  ) async {
    try {
      final backupInfo =
          await encryption.keyManager.getRoomKeysBackupInfo(false);
      final authData = Map<String, Object?>.from(backupInfo.authData);

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
    }
  }

  // ── Internals ─────────────────────────────────────────────────

  void _advance(dynamic Function() fn) {
    unawaited(Future.microtask(fn));
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
    _verification?.onUpdate = null;
    super.dispose();
  }
}

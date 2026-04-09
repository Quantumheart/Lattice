import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/e2ee/widgets/bootstrap_controller.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

class BootstrapDriver {
  BootstrapDriver({
    required this.matrixService,
    required bool wipeExisting,
    required this.onPhaseChanged,
    required this.onNewSsss,
    required this.onOpenExistingSsss,
    required this.onDone,
    required this.onError,
  }) : _wipeExisting = wipeExisting;

  final MatrixService matrixService;
  final void Function(SetupPhase phase) onPhaseChanged;
  final VoidCallback onNewSsss;
  final VoidCallback onOpenExistingSsss;
  final Future<void> Function() onDone;
  final void Function(String error) onError;

  // ── State ─────────────────────────────────────────────────────

  Bootstrap? _bootstrap;
  BootstrapState _state = BootstrapState.loading;
  bool _wipeExisting;
  bool _awaitingKeyAck = false;
  bool _isDisposed = false;

  Bootstrap? get bootstrap => _bootstrap;
  BootstrapState get state => _state;

  String get loadingMessage => switch (_state) {
        BootstrapState.askSetupCrossSigning => 'Setting up cross-signing...',
        BootstrapState.askSetupOnlineKeyBackup => 'Setting up key backup...',
        _ => 'Preparing...',
      };

  // ── Lifecycle ─────────────────────────────────────────────────

  Future<void> start() async {
    final client = matrixService.client;
    final encryption = client.encryption;
    if (encryption == null) {
      _state = BootstrapState.error;
      onError('Encryption is not available');
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
      onError('Timed out waiting for sync. Check your connection and retry.');
      return;
    } catch (e, s) {
      debugPrint('[Bootstrap] Sync preparation failed: $e\n$s');
      if (_isDisposed) return;
      _state = BootstrapState.error;
      onError('Failed to sync before bootstrap: $e');
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

    if (_awaitingKeyAck && _state != BootstrapState.error) {
      return;
    }

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
        onPhaseChanged(SetupPhase.loading);
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
        onPhaseChanged(SetupPhase.loading);
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
        unawaited(onDone());
        return;
      default:
        break;
    }

    final phase = _phaseFromState(_state);
    onPhaseChanged(phase);

    if (_state == BootstrapState.askNewSsss) {
      _awaitingKeyAck = true;
      onNewSsss();
    }
    if (_state == BootstrapState.openExistingSsss) {
      onOpenExistingSsss();
    }
  }

  static SetupPhase _phaseFromState(BootstrapState state) => switch (state) {
        BootstrapState.askNewSsss => SetupPhase.savingKey,
        BootstrapState.openExistingSsss => SetupPhase.unlock,
        BootstrapState.error => SetupPhase.error,
        _ => SetupPhase.loading,
      };

  // ── Actions ───────────────────────────────────────────────────

  void confirmNewSsss() {
    _awaitingKeyAck = false;
    if (_bootstrap != null) {
      _onBootstrapUpdate(_bootstrap!);
    }
  }

  void restart({bool wipe = false}) {
    if (wipe) _wipeExisting = true;
    _bootstrap = null;
    _state = BootstrapState.loading;
    _awaitingKeyAck = false;
    unawaited(start());
  }

  // ── Internals ─────────────────────────────────────────────────

  void _advance(dynamic Function() fn) {
    unawaited(Future.microtask(fn));
  }

  void dispose() {
    _isDisposed = true;
  }
}

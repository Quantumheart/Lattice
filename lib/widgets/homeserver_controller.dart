import 'package:flutter/foundation.dart';

import '../services/matrix_service.dart';

// ── HomeserverState ────────────────────────────────────────────────────────────

/// States for the homeserver selection screen state machine.
enum HomeserverState {
  idle,
  checking,
  ready,
  error,
}

// ── HomeserverController ───────────────────────────────────────────────────────

/// Business logic for the homeserver selection step.
///
/// Probes a homeserver URL and fetches its authentication capabilities
/// before handing off to the login screen.
class HomeserverController extends ChangeNotifier {
  HomeserverController({required this.matrixService});

  final MatrixService matrixService;

  // ── State fields ──────────────────────────────────────────────

  HomeserverState _state = HomeserverState.idle;
  HomeserverState get state => _state;

  String? _error;
  String? get error => _error;

  ServerAuthCapabilities? _capabilities;
  ServerAuthCapabilities? get capabilities => _capabilities;

  bool _isDisposed = false;
  int _checkGeneration = 0;

  // ── Server check ──────────────────────────────────────────────

  Future<ServerAuthCapabilities?> checkServer(String homeserver) async {
    _state = HomeserverState.checking;
    _capabilities = null;
    _error = null;
    _notify();

    final generation = ++_checkGeneration;

    try {
      final caps =
          await matrixService.getServerAuthCapabilities(homeserver);
      if (_isDisposed || generation != _checkGeneration) return null;

      _capabilities = caps;

      if (!caps.supportsPassword && !caps.supportsSso) {
        _state = HomeserverState.error;
        _error = 'This server does not support password or SSO login';
        _notify();
        return null;
      } else {
        _state = HomeserverState.ready;
        _notify();
        return caps;
      }
    } catch (e) {
      if (_isDisposed || generation != _checkGeneration) return null;
      _state = HomeserverState.error;
      _error = MatrixService.friendlyAuthError(e);
      _notify();
      return null;
    }
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

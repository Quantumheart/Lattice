import 'dart:async';

import 'package:flutter/foundation.dart';

enum CallState { joining, connected, reconnecting, ended }

class CallController extends ChangeNotifier {
  CallController({required this.roomId, required this.displayName});

  final String roomId;
  final String displayName;

  // ── State fields ──────────────────────────────────────────────

  CallState _state = CallState.joining;
  String? _error;
  bool _isDisposed = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  // ── Public getters ────────────────────────────────────────────

  CallState get state => _state;
  String? get error => _error;
  Duration get elapsed => _elapsed;

  // ── Join / hang up ────────────────────────────────────────────

  Future<void> join() async {
    debugPrint('[Lattice] CallController: joining room $roomId');
    _state = CallState.joining;
    _notify();

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_isDisposed) return;

    debugPrint('[Lattice] CallController: connected');
    _state = CallState.connected;
    _startTimer();
    _notify();
  }

  void hangUp() {
    debugPrint('[Lattice] CallController: hanging up');
    _stopTimer();
    _state = CallState.ended;
    _notify();
  }

  void endWithError(String message) {
    _error = message;
    _state = CallState.ended;
    _notify();
  }

  // ── Elapsed timer ─────────────────────────────────────────────

  void _startTimer() {
    _elapsed = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      _notify();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
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
    _stopTimer();
    super.dispose();
  }
}

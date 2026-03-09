import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/features/calling/models/call_participant.dart';

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
  List<CallParticipant> _participants = [];

  // ── Public getters ────────────────────────────────────────────

  CallState get state => _state;
  String? get error => _error;
  Duration get elapsed => _elapsed;
  List<CallParticipant> get participants => List.unmodifiable(_participants);

  // ── Join / hang up ────────────────────────────────────────────

  Future<void> join() async {
    debugPrint('[Lattice] CallController: joining room $roomId');
    _state = CallState.joining;
    _notify();

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_isDisposed) return;

    debugPrint('[Lattice] CallController: connected');
    _state = CallState.connected;
    _initMockParticipants();
    _startTimer();
    _notify();
  }

  void hangUp() {
    debugPrint('[Lattice] CallController: hanging up');
    _participants = [];
    _stopTimer();
    _state = CallState.ended;
    _notify();
  }

  void endWithError(String message) {
    _error = message;
    _state = CallState.ended;
    _notify();
  }

  // ── Mock participants ────────────────────────────────────────

  void _initMockParticipants() {
    _participants = [
      CallParticipant(
        id: 'local',
        displayName: displayName,
        isLocal: true,
        audioLevel: 0.3,
      ),
      const CallParticipant(
        id: 'remote-1',
        displayName: 'Alice',
        isSpeaking: true,
        audioLevel: 0.7,
      ),
      const CallParticipant(
        id: 'remote-2',
        displayName: 'Bob',
        isAudioOnly: true,
        audioLevel: 0.1,
      ),
      const CallParticipant(
        id: 'remote-3',
        displayName: 'Charlie',
        isMuted: true,
      ),
    ];
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

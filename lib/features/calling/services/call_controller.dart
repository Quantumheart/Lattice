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

  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _isScreenSharing = false;

  // ── Public getters ────────────────────────────────────────────

  CallState get state => _state;
  String? get error => _error;
  Duration get elapsed => _elapsed;
  List<CallParticipant> get participants => List.unmodifiable(_participants);
  bool get isMicMuted => _isMicMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isFrontCamera => _isFrontCamera;
  bool get isScreenSharing => _isScreenSharing;

  // ── Join / hang up ────────────────────────────────────────────

  Future<void> join() async {
    if (_state != CallState.joining) return;
    debugPrint('[Lattice] CallController: joining room $roomId');

    // TODO(lattice): replace with real WebRTC/LiveKit connection
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_isDisposed) return;

    debugPrint('[Lattice] CallController: connected');
    _state = CallState.connected;
    _participants = _buildMockParticipants();
    _startTimer();
    _notify();
  }

  void hangUp() {
    debugPrint('[Lattice] CallController: hanging up');
    _participants = [];
    _isMicMuted = false;
    _isCameraOff = false;
    _isFrontCamera = true;
    _isScreenSharing = false;
    _stopTimer();
    _state = CallState.ended;
    _notify();
  }

  void endWithError(String message) {
    _error = message;
    _state = CallState.ended;
    _notify();
  }

  // ── Mock participants (TODO(lattice): replace with real tracking) ──

  List<CallParticipant> _buildMockParticipants() {
    return [
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

  // ── Media controls ───────────────────────────────────────────

  void toggleMic() {
    _isMicMuted = !_isMicMuted;
    _updateLocalParticipant((p) => p.copyWith(isMuted: _isMicMuted));
  }

  void toggleCamera() {
    _isCameraOff = !_isCameraOff;
    _updateLocalParticipant(
      (p) => p.copyWith(isAudioOnly: _isCameraOff),
    );
  }

  void flipCamera() {
    _isFrontCamera = !_isFrontCamera;
    _notify();
  }

  void toggleScreenShare() {
    _isScreenSharing = !_isScreenSharing;
    _updateLocalParticipant(
      (p) => p.copyWith(isScreenSharing: _isScreenSharing),
    );
  }

  void _updateLocalParticipant(
    CallParticipant Function(CallParticipant) updater,
  ) {
    _participants = [
      for (final p in _participants)
        if (p.isLocal) updater(p) else p,
    ];
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

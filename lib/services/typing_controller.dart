import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Manages outgoing typing indicators for a single room.
///
/// Debounces `setTyping(true)` calls so the server is notified at most once
/// every [_sendInterval], and automatically stops typing after [_inactivityTimeout]
/// of silence.
class TypingController {
  TypingController({required this.room});

  final Room room;

  static const _sendInterval = Duration(seconds: 4);
  static const _inactivityTimeout = Duration(seconds: 30);

  bool _isTyping = false;
  DateTime? _lastSentAt;
  Timer? _inactivityTimer;

  /// Call when the compose text changes.
  void onTextChanged(String text) {
    if (text.isEmpty) {
      stop();
      return;
    }

    _resetInactivityTimer();

    final now = clock.now();
    if (_isTyping &&
        _lastSentAt != null &&
        now.difference(_lastSentAt!) < _sendInterval) {
      return;
    }

    _isTyping = true;
    _lastSentAt = now;
    _sendTyping(true);
  }

  /// Stop broadcasting typing. Idempotent.
  void stop() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    if (!_isTyping) return;
    _isTyping = false;
    _lastSentAt = null;
    _sendTyping(false);
  }

  void dispose() {
    stop();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, stop);
  }

  void _sendTyping(bool typing) {
    room.setTyping(typing, timeout: typing ? _inactivityTimeout.inMilliseconds : null).catchError((e) {
      debugPrint('[Lattice] Failed to set typing: $e');
    });
  }
}

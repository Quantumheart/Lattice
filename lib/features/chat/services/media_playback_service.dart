import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

// ── Single-active-player enforcement ──────────────────────────

class MediaPlaybackService extends ChangeNotifier {
  String? _activeEventId;
  Player? _activePlayer;

  String? get activeEventId => _activeEventId;

  void registerPlayer(String eventId, Player player) {
    if (_activeEventId != null && _activeEventId != eventId) {
      _activePlayer?.pause();
    }
    _activeEventId = eventId;
    _activePlayer = player;
    notifyListeners();
  }

  void unregisterPlayer(String eventId) {
    if (_activeEventId == eventId) {
      _activeEventId = null;
      _activePlayer = null;
      notifyListeners();
    }
  }

  void pauseActive() {
    _activePlayer?.pause();
  }

  @override
  void dispose() {
    _activePlayer?.pause();
    _activePlayer = null;
    _activeEventId = null;
    super.dispose();
  }
}

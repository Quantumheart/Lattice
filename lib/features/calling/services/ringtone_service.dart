import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

// coverage:ignore-start
class RingtoneService {
  Player? _player;

  Player _ensurePlayer() => _player ??= Player();

  Future<void> playRingtone({bool loop = true}) async {
    await stop();
    await _ensurePlayer().open(Media('asset:///assets/audio/ringtone.mp3'));
    if (loop) {
      await _player!.setPlaylistMode(PlaylistMode.loop);
    }
    if (!kIsWeb) unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
  }

  Future<void> playDialtone({bool loop = true}) async {
    await stop();
    await _ensurePlayer().open(Media('asset:///assets/audio/dialtone.mp3'));
    if (loop) {
      await _player!.setPlaylistMode(PlaylistMode.loop);
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  // ── PTT sounds ──────────────────────────────────────────────

  Player? _pttPlayer;

  Player _ensurePttPlayer() => _pttPlayer ??= Player();

  Future<void> playPTTOn() async {
    await _ensurePttPlayer().open(Media('asset:///assets/audio/ptt_on.mp3'));
  }

  Future<void> playPTTOff() async {
    await _ensurePttPlayer().open(Media('asset:///assets/audio/ptt_off.mp3'));
  }

  // ── Participant join/leave sounds ──────────────────────────

  final List<Player?> _participantPlayers = [null, null];
  int _participantPlayerIndex = 0;

  Player _nextParticipantPlayer() {
    final idx = _participantPlayerIndex;
    _participantPlayerIndex = (idx + 1) % _participantPlayers.length;
    return _participantPlayers[idx] ??= Player();
  }

  Future<void> playUserJoined() async {
    try {
      await _nextParticipantPlayer()
          .open(Media('asset:///assets/audio/user_join.mp3'));
    } catch (e) {
      debugPrint('[Kohera] playUserJoined failed: $e');
    }
  }

  Future<void> playUserLeft() async {
    try {
      await _nextParticipantPlayer()
          .open(Media('asset:///assets/audio/user_leave.mp3'));
    } catch (e) {
      debugPrint('[Kohera] playUserLeft failed: $e');
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    try {
      await _pttPlayer?.dispose();
    } catch (_) {}
    _pttPlayer = null;
    for (var i = 0; i < _participantPlayers.length; i++) {
      try {
        await _participantPlayers[i]?.dispose();
      } catch (_) {}
      _participantPlayers[i] = null;
    }
  }
}
// coverage:ignore-end

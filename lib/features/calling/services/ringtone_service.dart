import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

class RingtoneService {
  Player? _player;

  Player _ensurePlayer() => _player ??= Player();

  Future<void> playRingtone({bool loop = true}) async {
    if (kIsWeb) return;
    await stop();
    await _ensurePlayer().open(Media('asset:///assets/audio/ringtone.ogg'));
    if (loop) {
      await _player!.setPlaylistMode(PlaylistMode.loop);
    }
    unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
  }

  Future<void> playDialtone({bool loop = true}) async {
    if (kIsWeb) return;
    await stop();
    await _ensurePlayer().open(Media('asset:///assets/audio/dialtone.ogg'));
    if (loop) {
      await _player!.setPlaylistMode(PlaylistMode.loop);
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}

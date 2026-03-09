import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

class RingtoneService {
  Player? _player;

  Future<void> playRingtone({bool loop = true}) async {
    if (kIsWeb) return;
    await stop();
    _player = Player();
    await _player!.open(Media('asset:///assets/audio/ringtone.ogg'));
    if (loop) {
      await _player!.setPlaylistMode(PlaylistMode.single);
    }
    unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
  }

  Future<void> playDialtone({bool loop = true}) async {
    if (kIsWeb) return;
    await stop();
    _player = Player();
    await _player!.open(Media('asset:///assets/audio/dialtone.ogg'));
    if (loop) {
      await _player!.setPlaylistMode(PlaylistMode.single);
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }

  Future<void> dispose() async {
    await stop();
  }
}

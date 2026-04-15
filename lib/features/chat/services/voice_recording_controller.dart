import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/media_cache_io.dart'
    if (dart.library.js_interop) 'package:kohera/core/utils/media_cache_web.dart';
import 'package:kohera/features/chat/services/voice_recording_service.dart';
import 'package:path_provider/path_provider.dart';

// coverage:ignore-start

enum VoiceRecordingState { idle, requesting, recording, stopping }

class VoiceRecordingController extends ChangeNotifier {
  final _service = VoiceRecordingService();

  VoiceRecordingState _state = VoiceRecordingState.idle;
  VoiceRecordingState get state => _state;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  Duration _finalElapsed = Duration.zero;
  Duration get finalElapsed => _finalElapsed;

  Timer? _timer;
  String? _filePath;

  Future<bool> startRecording() async {
    if (_state != VoiceRecordingState.idle) return false;

    _state = VoiceRecordingState.requesting;
    notifyListeners();

    final granted = await _service.hasPermission();
    if (!granted) {
      _state = VoiceRecordingState.idle;
      notifyListeners();
      return false;
    }

    if (kIsWeb) {
      _filePath = 'recording.opus';
    } else {
      final dir = await getTemporaryDirectory();
      _filePath =
          '${dir.path}/kohera_voice_${DateTime.now().millisecondsSinceEpoch}.mp3';
    }

    await _service.start(_filePath!);

    _elapsed = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });

    _state = VoiceRecordingState.recording;
    notifyListeners();
    return true;
  }

  Future<String?> stopRecording() async {
    if (_state != VoiceRecordingState.recording) return null;

    _state = VoiceRecordingState.stopping;
    _timer?.cancel();
    _timer = null;
    _finalElapsed = _elapsed;
    notifyListeners();

    final path = await _service.stop();

    _state = VoiceRecordingState.idle;
    _elapsed = Duration.zero;
    _filePath = null;
    notifyListeners();
    return path;
  }

  Future<void> cancelRecording() async {
    if (_state != VoiceRecordingState.recording) return;

    _timer?.cancel();
    _timer = null;
    await _service.cancel();

    if (_filePath != null && !kIsWeb) {
      try {
        await File(_filePath!).delete();
      } catch (_) {}
    }

    _state = VoiceRecordingState.idle;
    _elapsed = Duration.zero;
    _filePath = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_service.dispose());
    super.dispose();
  }
}
// coverage:ignore-end

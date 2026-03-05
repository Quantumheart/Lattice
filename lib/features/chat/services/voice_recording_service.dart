import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class VoiceRecordingService {
  final _recorder = AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start(String path) async {
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.opus),
      path: path,
    );
  }

  Future<String?> stop() => _recorder.stop();

  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (e) {
      debugPrint('[Lattice] Recording cancel failed: $e');
    }
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}

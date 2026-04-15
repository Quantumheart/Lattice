import 'package:flutter/material.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:kohera/features/chat/services/voice_recording_controller.dart';
import 'package:kohera/features/chat/widgets/voice_send_handler.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

mixin VoiceRecordingMixin<T extends StatefulWidget> on State<T> {
  VoiceRecordingController? get voiceController;
  ValueNotifier<UploadState?> get voiceUploadNotifier;
  String get voiceRoomId;

  Future<void> startVoiceRecording() async {
    context.read<MediaPlaybackService>().pauseActive();
    final started = await voiceController!.startRecording();
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
    }
  }

  Future<void> stopAndSendVoiceMessage() async {
    final elapsed = voiceController!.elapsed;
    final path = await voiceController!.stopRecording();
    if (path != null && mounted) {
      await sendVoiceMessage(
        context,
        voiceRoomId,
        voiceUploadNotifier,
        path,
        elapsed,
      );
    }
  }

  Future<void> cancelVoiceRecording() async {
    await voiceController?.cancelRecording();
  }
}
// coverage:ignore-end

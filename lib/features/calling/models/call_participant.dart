import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:webrtc_interface/webrtc_interface.dart' as webrtc;

@immutable
class CallParticipant {
  const CallParticipant({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.isLocal = false,
    this.isAudioOnly = false,
    this.isMuted = false,
    this.isSpeaking = false,
    this.isScreenSharing = false,
    this.audioLevel = 0.0,
    this.videoTrack,
    this.screenShareTrack,
    this.mediaStream,
  });

  final String id;
  final String displayName;
  final Uri? avatarUrl;
  final bool isLocal;
  final bool isAudioOnly;
  final bool isMuted;
  final bool isSpeaking;
  final bool isScreenSharing;
  final double audioLevel;
  final livekit.VideoTrack? videoTrack;
  final livekit.VideoTrack? screenShareTrack;
  final webrtc.MediaStream? mediaStream;

  bool get hasVideo => videoTrack != null || mediaStream != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallParticipant &&
          id == other.id &&
          displayName == other.displayName &&
          avatarUrl == other.avatarUrl &&
          isLocal == other.isLocal &&
          isAudioOnly == other.isAudioOnly &&
          isMuted == other.isMuted &&
          isSpeaking == other.isSpeaking &&
          isScreenSharing == other.isScreenSharing &&
          audioLevel == other.audioLevel &&
          videoTrack == other.videoTrack &&
          screenShareTrack == other.screenShareTrack &&
          mediaStream == other.mediaStream;

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        avatarUrl,
        isLocal,
        isAudioOnly,
        isMuted,
        isSpeaking,
        isScreenSharing,
        audioLevel,
        videoTrack,
        screenShareTrack,
        mediaStream,
      );
}

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
    this.mediaStream,
  });

  factory CallParticipant.fromLiveKit(
    livekit.Participant p, {
    List<livekit.Participant> activeSpeakers = const [],
    bool isLocal = false,
    Uri? avatarUrl,
  }) {
    final cameraPub = p.videoTrackPublications
        .where((pub) => pub.source != livekit.TrackSource.screenShareVideo)
        .firstOrNull;
    final hasVideo = cameraPub != null && cameraPub.subscribed && !cameraPub.muted;
    final track = hasVideo ? cameraPub.track : null;
    final videoTrack = track is livekit.VideoTrack ? track : null;

    final hasScreenShare = p.videoTrackPublications.any(
      (pub) => pub.source == livekit.TrackSource.screenShareVideo && pub.subscribed,
    );
    final matrixId = extractMatrixId(p.identity);
    return CallParticipant(
      id: matrixId,
      displayName: p.name.isNotEmpty ? p.name : _displayNameFromIdentity(p.identity),
      avatarUrl: avatarUrl,
      isLocal: isLocal,
      isAudioOnly: !hasVideo,
      isMuted: p.isMuted,
      isSpeaking: activeSpeakers.any((s) => s.identity == p.identity),
      isScreenSharing: hasScreenShare,
      audioLevel: p.audioLevel,
      videoTrack: videoTrack,
    );
  }

  static final _matrixIdPattern = RegExp('@[^:]+:[^:]+');

  static String extractMatrixId(String identity) {
    final match = _matrixIdPattern.firstMatch(identity);
    return match?.group(0) ?? identity;
  }

  static String _displayNameFromIdentity(String identity) {
    final match = RegExp('@([^:]+)').firstMatch(identity);
    return match?.group(1) ?? identity;
  }

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
        mediaStream,
      );
}

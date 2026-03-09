import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

@immutable
class CallParticipant {
  const CallParticipant({
    required this.id,
    required this.displayName,
    this.isLocal = false,
    this.isAudioOnly = false,
    this.isMuted = false,
    this.isSpeaking = false,
    this.isScreenSharing = false,
    this.audioLevel = 0.0,
  });

  factory CallParticipant.fromRemote(
    livekit.RemoteParticipant p, {
    List<livekit.Participant> activeSpeakers = const [],
  }) {
    final hasVideo = p.videoTrackPublications.any(
      (pub) => pub.subscribed && !pub.muted,
    );
    final hasScreenShare = p.videoTrackPublications.any(
      (pub) => pub.source == livekit.TrackSource.screenShareVideo && pub.subscribed,
    );
    return CallParticipant(
      id: p.identity,
      displayName: p.name.isNotEmpty ? p.name : p.identity,
      isAudioOnly: !hasVideo,
      isMuted: p.isMuted,
      isSpeaking: activeSpeakers.any((s) => s.identity == p.identity),
      isScreenSharing: hasScreenShare,
    );
  }

  final String id;
  final String displayName;
  final bool isLocal;
  final bool isAudioOnly;
  final bool isMuted;
  final bool isSpeaking;
  final bool isScreenSharing;
  final double audioLevel;

  CallParticipant copyWith({
    String? id,
    String? displayName,
    bool? isLocal,
    bool? isAudioOnly,
    bool? isMuted,
    bool? isSpeaking,
    bool? isScreenSharing,
    double? audioLevel,
  }) {
    return CallParticipant(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      isLocal: isLocal ?? this.isLocal,
      isAudioOnly: isAudioOnly ?? this.isAudioOnly,
      isMuted: isMuted ?? this.isMuted,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      audioLevel: audioLevel ?? this.audioLevel,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallParticipant &&
          id == other.id &&
          displayName == other.displayName &&
          isLocal == other.isLocal &&
          isAudioOnly == other.isAudioOnly &&
          isMuted == other.isMuted &&
          isSpeaking == other.isSpeaking &&
          isScreenSharing == other.isScreenSharing &&
          audioLevel == other.audioLevel;

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        isLocal,
        isAudioOnly,
        isMuted,
        isSpeaking,
        isScreenSharing,
        audioLevel,
      );
}

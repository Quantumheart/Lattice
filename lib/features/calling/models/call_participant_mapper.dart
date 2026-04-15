import 'package:kohera/features/calling/models/call_participant.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

class CallParticipantMapper {
  CallParticipantMapper._();

  static final _matrixIdPattern = RegExp('@[^:]+:[^:]+');

  static String extractMatrixId(String identity) {
    final match = _matrixIdPattern.firstMatch(identity);
    return match?.group(0) ?? identity;
  }

  static String _displayNameFromIdentity(String identity) {
    final match = RegExp('@([^:]+)').firstMatch(identity);
    return match?.group(1) ?? identity;
  }

  static CallParticipant fromLiveKit(
    livekit.Participant p, {
    List<livekit.Participant> activeSpeakers = const [],
    bool isLocal = false,
    Uri? avatarUrl,
  }) {
    final cameraPub = p.videoTrackPublications
        .where((pub) => pub.source != livekit.TrackSource.screenShareVideo)
        .firstOrNull;
    final hasVideo =
        cameraPub != null && cameraPub.subscribed && !cameraPub.muted;
    final track = hasVideo ? cameraPub.track : null;
    final videoTrack = track is livekit.VideoTrack ? track : null;

    final screenSharePub = p.videoTrackPublications
        .where(
          (pub) =>
              pub.source == livekit.TrackSource.screenShareVideo &&
              !pub.muted,
        )
        .firstOrNull;
    final screenShareRawTrack = screenSharePub?.track;
    final screenShareTrack = screenShareRawTrack is livekit.VideoTrack
        ? screenShareRawTrack
        : null;

    final matrixId = extractMatrixId(p.identity);

    return CallParticipant(
      id: matrixId,
      displayName: p.name.isNotEmpty ? p.name : _displayNameFromIdentity(p.identity),
      avatarUrl: avatarUrl,
      isLocal: isLocal,
      isAudioOnly: !hasVideo,
      isMuted: p.isMuted,
      isSpeaking: activeSpeakers.any((s) => s.identity == p.identity),
      audioLevel: p.audioLevel,
      videoTrack: videoTrack,
      screenShareTrack: screenShareTrack,
    );
  }
}

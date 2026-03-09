class CallParticipant {
  const CallParticipant({
    required this.id,
    required this.displayName,
    this.isLocal = false,
    this.isAudioOnly = false,
    this.isMuted = false,
    this.isCameraOff = false,
    this.isSpeaking = false,
    this.audioLevel = 0.0,
  });

  final String id;
  final String displayName;
  final bool isLocal;
  final bool isAudioOnly;
  final bool isMuted;
  final bool isCameraOff;
  final bool isSpeaking;
  final double audioLevel;

  CallParticipant copyWith({
    String? id,
    String? displayName,
    bool? isLocal,
    bool? isAudioOnly,
    bool? isMuted,
    bool? isCameraOff,
    bool? isSpeaking,
    double? audioLevel,
  }) {
    return CallParticipant(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      isLocal: isLocal ?? this.isLocal,
      isAudioOnly: isAudioOnly ?? this.isAudioOnly,
      isMuted: isMuted ?? this.isMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      audioLevel: audioLevel ?? this.audioLevel,
    );
  }
}

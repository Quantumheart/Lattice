enum CallType { voice, video }

class IncomingCallInfo {
  const IncomingCallInfo({
    required this.roomId,
    required this.callerName,
    this.callerAvatarUrl,
    this.isVideo = false,
    this.isGroupCall = false,
  });

  final String roomId;
  final String callerName;
  final Uri? callerAvatarUrl;
  final bool isVideo;
  final bool isGroupCall;
}

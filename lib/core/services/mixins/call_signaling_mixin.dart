import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/models/call_constants.dart';
import 'package:lattice/features/calling/models/incoming_call_info.dart' as model;
import 'package:matrix/matrix.dart';

mixin CallSignalingMixin on ChangeNotifier {
  // ── Cross-mixin dependencies ──────────────────────────────────
  Client get client;
  LatticeCallState get callState;
  @protected
  set callState(LatticeCallState value);
  void handleCallEnded();
  Future<void> joinCall(String roomId);
  Future<void> leaveCall();
  void stopRinging();
  @protected
  void pushIncomingCall(model.IncomingCallInfo info);
  @protected
  void playRingtone();

  // ── State ─────────────────────────────────────────────────────
  String? _activeCallId;
  String? get activeCallId => _activeCallId;

  StreamSubscription<Event>? _signalingEventSub;

  // ── Call ID generation ────────────────────────────────────────
  static final _random = Random();

  static String _generateCallId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(0xFFFF).toRadixString(36).padLeft(3, '0');
    return '$timestamp$suffix';
  }

  // ── Event senders ─────────────────────────────────────────────
  Future<void> sendCallInvite(String roomId, {bool isVideo = false}) async {
    final callId = _generateCallId();
    _activeCallId = callId;
    final room = client.getRoomById(roomId);
    if (room == null) return;
    await room.sendEvent({
      'call_id': callId,
      'version': 1,
      'lifetime': 60000,
      'offer': {'type': 'offer', 'sdp': ''},
      'is_video': isVideo,
    }, type: kCallInvite,);
    debugPrint('[Lattice] Sent m.call.invite for call $callId in $roomId');
  }

  Future<void> sendCallAnswer(String roomId, String callId) async {
    final room = client.getRoomById(roomId);
    if (room == null) return;
    await room.sendEvent({
      'call_id': callId,
      'version': 1,
    }, type: kCallAnswer,);
    debugPrint('[Lattice] Sent m.call.answer for call $callId in $roomId');
  }

  Future<void> sendCallReject(String roomId, String callId) async {
    final room = client.getRoomById(roomId);
    if (room == null) return;
    await room.sendEvent({
      'call_id': callId,
      'version': 1,
    }, type: kCallReject,);
    debugPrint('[Lattice] Sent m.call.reject for call $callId in $roomId');
  }

  Future<void> sendCallHangup(
    String roomId,
    String callId, {
    String reason = kHangupUserHangup,
  }) async {
    final room = client.getRoomById(roomId);
    if (room == null) return;
    await room.sendEvent({
      'call_id': callId,
      'version': 1,
      'reason': reason,
    }, type: kCallHangup,);
    debugPrint('[Lattice] Sent m.call.hangup ($reason) for call $callId in $roomId');
  }

  // ── Listener ──────────────────────────────────────────────────
  @protected
  void startSignalingListener() {
    unawaited(_signalingEventSub?.cancel());
    _signalingEventSub = client.onTimelineEvent.stream.listen(_onTimelineEvent);
    debugPrint('[Lattice] Call signaling listener started');
  }

  @protected
  void stopSignalingListener() {
    unawaited(_signalingEventSub?.cancel());
    _signalingEventSub = null;
  }

  void _onTimelineEvent(Event event) {
    if (!callEventTypes.contains(event.type)) return;

    final room = event.room;
    if (!room.isDirectChat) return;

    if (event.senderId == client.userID) return;

    switch (event.type) {
      case kCallInvite:
        _handleIncomingInvite(event);
      case kCallAnswer:
        _handleAnswer(event);
      case kCallReject:
        _handleReject(event);
      case kCallHangup:
        _handleHangup(event);
    }
  }

  // ── Handlers ──────────────────────────────────────────────────
  void _handleIncomingInvite(Event event) {
    if (callState != LatticeCallState.idle) {
      if (callState == LatticeCallState.ringingOutgoing) {
        _resolveGlare(event);
      }
      return;
    }

    final content = event.content;
    final callId = content.tryGet<String>('call_id');
    if (callId == null) return;

    final lifetime = content.tryGet<int>('lifetime') ?? 60000;
    final expiresAt = event.originServerTs.millisecondsSinceEpoch + lifetime;
    if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
      debugPrint('[Lattice] Ignoring stale call invite $callId');
      return;
    }

    final isVideo = content.tryGet<bool>('is_video') ?? false;
    final sender = event.senderFromMemoryOrFallback;

    _activeCallId = callId;

    final info = model.IncomingCallInfo(
      roomId: event.roomId!,
      callerName: sender.calcDisplayname(),
      callId: callId,
      callerAvatarUrl: sender.avatarUrl,
      isVideo: isVideo,
    );

    pushIncomingCall(info);
    callState = LatticeCallState.ringingIncoming;
    playRingtone();

    debugPrint('[Lattice] Incoming call $callId from ${sender.calcDisplayname()}');
  }

  void _resolveGlare(Event event) {
    final theirCallId = event.content.tryGet<String>('call_id');
    if (theirCallId == null) return;
    final myUserId = client.userID ?? '';
    final theirUserId = event.senderId;

    final iWin = myUserId.compareTo(theirUserId) < 0;
    if (iWin) {
      debugPrint('[Lattice] Glare: I win, ignoring their invite');
      return;
    }

    debugPrint('[Lattice] Glare: I lose, accepting their invite');
    final myCallId = _activeCallId;
    final roomId = event.roomId!;
    if (myCallId != null) {
      unawaited(sendCallHangup(roomId, myCallId, reason: 'glare'));
    }

    _activeCallId = null;
    stopRinging();
    callState = LatticeCallState.idle;
    _handleIncomingInvite(event);
  }

  void _handleAnswer(Event event) {
    final callId = event.content.tryGet<String>('call_id');
    if (callId == null || callId != _activeCallId) return;
    if (callState != LatticeCallState.ringingOutgoing) return;

    debugPrint('[Lattice] Call $callId answered');
    unawaited(joinCall(event.roomId!));
  }

  void _handleReject(Event event) {
    final callId = event.content.tryGet<String>('call_id');
    if (callId == null || callId != _activeCallId) return;
    if (callState != LatticeCallState.ringingOutgoing) return;

    debugPrint('[Lattice] Call $callId rejected');
    _activeCallId = null;
    stopRinging();
    callState = LatticeCallState.idle;
  }

  void _handleHangup(Event event) {
    final callId = event.content.tryGet<String>('call_id');
    if (callId == null || callId != _activeCallId) return;

    debugPrint('[Lattice] Call $callId remote hangup');
    _activeCallId = null;

    if (callState == LatticeCallState.connected ||
        callState == LatticeCallState.reconnecting) {
      unawaited(leaveCall());
    } else {
      handleCallEnded();
    }
  }

  @protected
  void clearActiveCallId() => _activeCallId = null;
}

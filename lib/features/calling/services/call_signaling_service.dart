import 'dart:async';

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:kohera/features/calling/models/incoming_call_info.dart' as model;
import 'package:matrix/matrix.dart';

// ── Signaling Events ───────────────────────────────────────

sealed class SignalingEvent {}

class IncomingInvite extends SignalingEvent {
  IncomingInvite({required this.info, required this.callId});
  final model.IncomingCallInfo info;
  final String callId;
}

class AnswerReceived extends SignalingEvent {
  AnswerReceived({required this.roomId, required this.callId});
  final String roomId;
  final String callId;
}

class RejectReceived extends SignalingEvent {
  RejectReceived({required this.callId});
  final String callId;
}

class HangupReceived extends SignalingEvent {
  HangupReceived({required this.callId});
  final String callId;
}

class GlareResolved extends SignalingEvent {
  GlareResolved({required this.incomingInvite, required this.myCallId});
  final IncomingInvite incomingInvite;
  final String? myCallId;
}

// ── Call Signaling Service ─────────────────────────────────

class CallSignalingService {
  CallSignalingService({required Client client}) : _client = client;

  Client _client;

  void updateClient(Client client) => _client = client;

  StreamSubscription<Event>? _signalingEventSub;

  final _eventController = StreamController<SignalingEvent>.broadcast();
  Stream<SignalingEvent> get events => _eventController.stream;

  static final _random = Random();

  static String _generateCallId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final suffix =
        _random.nextInt(0xFFFFFFFF).toRadixString(36).padLeft(6, '0');
    return '$timestamp$suffix';
  }

  // ── Event Senders ──────────────────────────────────────────

  String generateCallId() => _generateCallId();

  Future<void> _prepareEncryption(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null || !room.encrypted) return;
    try {
      await _client.encryption?.keyManager
          .prepareOutboundGroupSession(roomId);
    } catch (e) {
      debugPrint('[Kohera] Failed to prepare encryption for call: $e');
    }
  }

  Future<void> sendCallInvite(
    String roomId,
    String callId, {
    bool isVideo = false,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    await _prepareEncryption(roomId);
    await room.sendEvent({
      'call_id': callId,
      'version': 1,
      'lifetime': 60000,
      'offer': {'type': 'offer', 'sdp': ''},
      'is_video': isVideo,
    }, type: kCallInvite,);
    debugPrint('[Kohera] Sent m.call.invite for call $callId in $roomId');
  }

  Future<void> sendCallAnswer(String roomId, String callId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    await _prepareEncryption(roomId);
    await room.sendEvent({
      'call_id': callId,
      'version': 1,
    }, type: kCallAnswer,);
    debugPrint('[Kohera] Sent m.call.answer for call $callId in $roomId');
  }

  Future<void> sendCallReject(String roomId, String callId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    await room.sendEvent({
      'call_id': callId,
      'version': 1,
    }, type: kCallReject,);
    debugPrint('[Kohera] Sent m.call.reject for call $callId in $roomId');
  }

  Future<void> sendCallHangup(
    String roomId,
    String callId, {
    String reason = kHangupUserHangup,
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    await room.sendEvent({
      'call_id': callId,
      'version': 1,
      'reason': reason,
    }, type: kCallHangup,);
    debugPrint('[Kohera] Sent m.call.hangup ($reason) for call $callId in $roomId');
  }

  // ── Listener ───────────────────────────────────────────────

  void startSignalingListener({
    required String? Function() getActiveCallId,
    required String Function() getCallState,
  }) {
    unawaited(_signalingEventSub?.cancel());
    _getActiveCallId = getActiveCallId;
    _getCallState = getCallState;
    _signalingEventSub = _client.onTimelineEvent.stream.listen(_onTimelineEvent);
    debugPrint('[Kohera] Call signaling listener started');
  }

  void stopSignalingListener() {
    unawaited(_signalingEventSub?.cancel());
    _signalingEventSub = null;
  }

  String? Function() _getActiveCallId = () => null;
  String Function() _getCallState = () => 'idle';

  void _onTimelineEvent(Event event) {
    if (!callEventTypes.contains(event.type)) return;
    if (event.roomId == null) return;

    final room = event.room;
    if (!room.isDirectChat) return;

    if (event.senderId == _client.userID) return;

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

  // ── Handlers ───────────────────────────────────────────────

  void _handleIncomingInvite(Event event) {
    final callState = _getCallState();
    if (callState != 'idle') {
      if (callState == 'ringingOutgoing') {
        _resolveGlare(event);
      }
      return;
    }

    final invite = _parseInvite(event);
    if (invite == null) return;

    _eventController.add(invite);
  }

  IncomingInvite? _parseInvite(Event event) {
    final content = event.content;
    final callId = content.tryGet<String>('call_id');
    if (callId == null) return null;

    final lifetime = content.tryGet<int>('lifetime') ?? 60000;
    final expiresAt = event.originServerTs.millisecondsSinceEpoch + lifetime;
    if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
      debugPrint('[Kohera] Ignoring stale call invite $callId');
      return null;
    }

    final isVideo = content.tryGet<bool>('is_video') ?? false;
    final sender = event.senderFromMemoryOrFallback;

    final info = model.IncomingCallInfo(
      roomId: event.roomId!,
      callerName: sender.calcDisplayname(),
      callId: callId,
      callerAvatarUrl: sender.avatarUrl,
      isVideo: isVideo,
    );

    debugPrint('[Kohera] Incoming call $callId from ${sender.calcDisplayname()}');
    return IncomingInvite(info: info, callId: callId);
  }

  void _resolveGlare(Event event) {
    final theirCallId = event.content.tryGet<String>('call_id');
    if (theirCallId == null) return;
    final myUserId = _client.userID ?? '';
    final theirUserId = event.senderId;

    final iWin = myUserId.compareTo(theirUserId) < 0;
    if (iWin) {
      debugPrint('[Kohera] Glare: I win, ignoring their invite');
      return;
    }

    debugPrint('[Kohera] Glare: I lose, accepting their invite');
    final myCallId = _getActiveCallId();
    final roomId = event.roomId!;
    if (myCallId != null) {
      unawaited(sendCallHangup(roomId, myCallId, reason: 'glare'));
    }

    final invite = _parseInvite(event);
    if (invite != null) {
      _eventController.add(GlareResolved(incomingInvite: invite, myCallId: myCallId));
    }
  }

  void _handleAnswer(Event event) {
    final callId = event.content.tryGet<String>('call_id');
    final activeCallId = _getActiveCallId();
    if (callId == null || callId != activeCallId) return;
    if (_getCallState() != 'ringingOutgoing') return;

    debugPrint('[Kohera] Call $callId answered');
    _eventController.add(AnswerReceived(roomId: event.roomId!, callId: callId));
  }

  void _handleReject(Event event) {
    final callId = event.content.tryGet<String>('call_id');
    final activeCallId = _getActiveCallId();
    if (callId == null || callId != activeCallId) return;
    if (_getCallState() != 'ringingOutgoing') return;

    debugPrint('[Kohera] Call $callId rejected');
    _eventController.add(RejectReceived(callId: callId));
  }

  void _handleHangup(Event event) {
    final callId = event.content.tryGet<String>('call_id');
    final activeCallId = _getActiveCallId();
    if (callId == null || callId != activeCallId) return;

    debugPrint('[Kohera] Call $callId remote hangup');
    _eventController.add(HangupReceived(callId: callId));
  }

  void dispose() {
    stopSignalingListener();
    unawaited(_eventController.close());
  }
}

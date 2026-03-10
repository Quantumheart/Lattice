import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/models/incoming_call_info.dart' as model;
import 'package:lattice/features/calling/services/ringtone_service.dart';

mixin CallRingingMixin on ChangeNotifier {
  // ── Cross-mixin dependencies ──────────────────────────────────
  LatticeCallState get callState;
  @protected
  set callState(LatticeCallState value);
  bool get initialized;
  void init();
  Future<void> joinCall(String roomId);
  Future<void> leaveCall();

  // ── Signaling dependencies ────────────────────────────────────
  Future<void> sendCallInvite(String roomId, {bool isVideo});
  Future<void> sendCallAnswer(String roomId, String callId);
  Future<void> sendCallReject(String roomId, String callId);
  Future<void> sendCallHangup(String roomId, String callId, {String reason});
  String? get activeCallId;

  // ── Ringtone ──────────────────────────────────────────────────
  RingtoneService? _ringtoneService;

  set ringtoneService(RingtoneService? service) => _ringtoneService = service;

  @protected
  RingtoneService? get ringtoneServiceInstance => _ringtoneService;

  @protected
  void stopRinging() {
    _ringingTimer?.cancel();
    _ringingTimer = null;
    unawaited(_ringtoneService?.stop());
  }

  @protected
  void playRingtone() {
    unawaited(_ringtoneService?.playRingtone());
  }

  @protected
  void disposeRingtone() {
    unawaited(_ringtoneService?.dispose());
    _ringtoneService = null;
  }

  // ── Ringing State ─────────────────────────────────────────────
  model.IncomingCallInfo? _incomingCall;
  model.IncomingCallInfo? get incomingCall => _incomingCall;

  Timer? _ringingTimer;

  final StreamController<model.IncomingCallInfo> _incomingCallController =
      StreamController<model.IncomingCallInfo>.broadcast();
  Stream<model.IncomingCallInfo> get incomingCallStream =>
      _incomingCallController.stream;

  @protected
  void pushIncomingCall(model.IncomingCallInfo info) {
    _incomingCall = info;
    _incomingCallController.add(info);
  }

  @protected
  void resetIncomingCall() => _incomingCall = null;

  @protected
  void closeIncomingCallController() => unawaited(_incomingCallController.close());

  // ── Incoming Call Handling ────────────────────────────────────
  @protected
  void handleCallEnded() {
    if (callState == LatticeCallState.joining) {
      callState = LatticeCallState.idle;
      return;
    }
    if (callState == LatticeCallState.ringingIncoming ||
        callState == LatticeCallState.ringingOutgoing) {
      _incomingCall = null;
      stopRinging();
      callState = LatticeCallState.idle;
    }
  }

  @visibleForTesting
  void simulateCallEnded() => handleCallEnded();

  // ── Ringing Actions ───────────────────────────────────────────
  void acceptCall({bool withVideo = false}) {
    if (callState != LatticeCallState.ringingIncoming) return;
    final info = _incomingCall;
    if (info == null) return;

    _incomingCall = null;
    stopRinging();

    if (info.callId != null) {
      unawaited(sendCallAnswer(info.roomId, info.callId!));
    }

    unawaited(joinCall(info.roomId));
  }

  void declineCall() {
    if (callState != LatticeCallState.ringingIncoming) return;
    final info = _incomingCall;

    if (info?.callId != null) {
      unawaited(sendCallReject(info!.roomId, info.callId!));
    }

    _incomingCall = null;
    callState = LatticeCallState.idle;
    stopRinging();
  }

  void cancelOutgoingCall({bool isTimeout = false}) {
    if (callState != LatticeCallState.ringingOutgoing &&
        callState != LatticeCallState.joining) {
      return;
    }

    final callId = activeCallId;
    if (callId != null && _lastInitiatedRoomId != null) {
      final reason = isTimeout ? 'invite_timeout' : 'user_hangup';
      unawaited(sendCallHangup(_lastInitiatedRoomId!, callId, reason: reason));
    }

    stopRinging();
    callState = LatticeCallState.idle;
  }

  String? _lastInitiatedRoomId;

  Future<void> initiateCall(String roomId, {model.CallType type = model.CallType.voice}) async {
    if (!initialized) init();
    if (callState != LatticeCallState.idle && callState != LatticeCallState.failed) return;

    _lastInitiatedRoomId = roomId;
    callState = LatticeCallState.ringingOutgoing;

    unawaited(_ringtoneService?.playDialtone());

    _ringingTimer = Timer(const Duration(seconds: 60), () => cancelOutgoingCall(isTimeout: true));

    await sendCallInvite(roomId, isVideo: type == model.CallType.video);
  }
}

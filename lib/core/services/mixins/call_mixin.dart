import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as webrtc;

// ── Call State ──────────────────────────────────────────────

enum LatticeCallState { idle, joining, connected, reconnecting, failed }

// ── WebRTC Delegate ─────────────────────────────────────────

class _LatticeWebRTCDelegate implements WebRTCDelegate {
  _LatticeWebRTCDelegate(this._onCallStateChanged);

  final VoidCallback _onCallStateChanged;

  bool _inCall = false;

  @override
  webrtc.MediaDevices get mediaDevices => flutter_webrtc.navigator.mediaDevices;

  @override
  Future<webrtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) =>
      flutter_webrtc.createPeerConnection(configuration, constraints);

  @override
  Future<void> playRingtone() async {}

  @override
  Future<void> stopRingtone() async {}

  @override
  Future<void> registerListeners(CallSession session) async {}

  @override
  Future<void> handleNewCall(CallSession session) async {
    _inCall = true;
    _onCallStateChanged();
  }

  @override
  Future<void> handleCallEnded(CallSession session) async {
    _inCall = false;
    _onCallStateChanged();
  }

  @override
  Future<void> handleMissedCall(CallSession session) async {}

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {
    _inCall = true;
    _onCallStateChanged();
  }

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {
    _inCall = false;
    _onCallStateChanged();
  }

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get canHandleNewCall => !_inCall;

  @override
  EncryptionKeyProvider? get keyProvider => null;
}

// ── Call Mixin ──────────────────────────────────────────────

mixin CallMixin on ChangeNotifier {
  Client get client;

  // ── VoIP ────────────────────────────────────────────────

  VoIP? _voip;
  VoIP? get voip => _voip;

  _LatticeWebRTCDelegate? _webrtcDelegate;

  void initVoip() {
    _webrtcDelegate = _LatticeWebRTCDelegate(notifyListeners);
    _voip = VoIP(client, _webrtcDelegate!);
    debugPrint('[Lattice] VoIP initialized');
  }

  @protected
  void disposeVoip() {
    _activeGroupCall = null;
    _callState = LatticeCallState.idle;
    _voip = null;
    _webrtcDelegate = null;
  }

  // ── State ───────────────────────────────────────────────

  LatticeCallState _callState = LatticeCallState.idle;
  LatticeCallState get callState => _callState;

  GroupCallSession? _activeGroupCall;
  GroupCallSession? get activeGroupCall => _activeGroupCall;

  String? get activeCallRoomId => _activeGroupCall?.room.id;

  StreamSubscription<MatrixRTCCallEvent>? _callEventSub;

  // ── Queries ─────────────────────────────────────────────

  bool roomHasActiveCall(String roomId) {
    if (_voip == null) return false;
    final room = client.getRoomById(roomId);
    if (room == null) return false;
    return room.hasActiveGroupCall(_voip!);
  }

  List<String> activeCallIdsForRoom(String roomId) {
    if (_voip == null) return const [];
    final room = client.getRoomById(roomId);
    if (room == null) return const [];
    return room.activeGroupCallIds(_voip!);
  }

  int callParticipantCount(String roomId, String groupCallId) {
    if (_voip == null) return 0;
    final room = client.getRoomById(roomId);
    if (room == null) return 0;
    return room.groupCallParticipantCount(groupCallId, _voip!);
  }

  List<CallMembership> callMembershipsForRoom(String roomId) {
    if (_voip == null) return const [];
    final room = client.getRoomById(roomId);
    if (room == null) return const [];
    final memberships = room.getCallMembershipsFromRoom(_voip!);
    return memberships.values.expand((list) => list).toList();
  }

  // ── Actions ─────────────────────────────────────────────

  Future<void> joinCall(
    String roomId, {
    CallBackend? backend,
    String? groupCallId,
  }) async {
    if (_voip == null) return;
    if (_callState != LatticeCallState.idle) {
      debugPrint('[Lattice] Cannot join call: already in state $_callState');
      return;
    }

    final room = client.getRoomById(roomId);
    if (room == null) {
      debugPrint('[Lattice] Cannot join call: room $roomId not found');
      return;
    }

    _callState = LatticeCallState.joining;
    notifyListeners();

    try {
      final resolvedBackend =
          backend ?? _resolveBackend(room, groupCallId);
      final resolvedCallId =
          groupCallId ?? _resolveGroupCallId(room);

      final groupCall = _findOrCreateGroupCall(
        room,
        resolvedBackend,
        resolvedCallId,
      );

      _activeGroupCall = groupCall;
      _callEventSub = groupCall.matrixRTCEventStream.stream.listen(
        _onMatrixRTCEvent,
      );

      await groupCall.enter();

      _callState = LatticeCallState.connected;
      notifyListeners();
      debugPrint(
        '[Lattice] Joined call ${groupCall.groupCallId} in room $roomId',
      );
    } catch (e) {
      debugPrint('[Lattice] Failed to join call: $e');
      _callState = LatticeCallState.failed;
      _activeGroupCall = null;
      unawaited(_callEventSub?.cancel());
      _callEventSub = null;
      notifyListeners();
    }
  }

  Future<void> leaveCall() async {
    if (_activeGroupCall == null) return;

    final callId = _activeGroupCall!.groupCallId;
    debugPrint('[Lattice] Leaving call $callId');

    try {
      await _activeGroupCall!.leave();
    } catch (e) {
      debugPrint('[Lattice] Error leaving call: $e');
    }

    unawaited(_callEventSub?.cancel());
    _callEventSub = null;
    _activeGroupCall = null;
    _callState = LatticeCallState.idle;
    notifyListeners();
  }

  // ── TURN Server ─────────────────────────────────────────

  Future<TurnServerCredentials?> fetchTurnServers() async {
    try {
      return await client.getTurnServer();
    } catch (e) {
      debugPrint('[Lattice] Failed to fetch TURN servers: $e');
      return null;
    }
  }

  // ── Private ─────────────────────────────────────────────

  GroupCallSession _findOrCreateGroupCall(
    Room room,
    CallBackend backend,
    String? callId,
  ) {
    if (callId != null) {
      final existing = _voip!.groupCalls.values.firstWhere(
        (gc) => gc.room.id == room.id && gc.groupCallId == callId,
        orElse: () => GroupCallSession.withAutoGenId(
          room,
          _voip!,
          backend,
          'm.call',
          'm.room',
          callId,
        ),
      );
      return existing;
    }

    return GroupCallSession.withAutoGenId(
      room,
      _voip!,
      backend,
      'm.call',
      'm.room',
      null,
    );
  }

  CallBackend _resolveBackend(Room room, String? groupCallId) {
    final callId = groupCallId ?? _resolveGroupCallId(room);
    if (callId != null && _voip != null) {
      final memberships = room.getCallMembershipsFromRoom(_voip!);
      for (final mems in memberships.values) {
        for (final mem in mems) {
          if (mem.callId == callId && !mem.isExpired) {
            return mem.backend;
          }
        }
      }
    }
    return MeshBackend();
  }

  String? _resolveGroupCallId(Room room) {
    if (_voip == null) return null;
    final ids = room.activeGroupCallIds(_voip!);
    return ids.isNotEmpty ? ids.first : null;
  }

  void _onMatrixRTCEvent(MatrixRTCCallEvent event) {
    switch (event) {
      case GroupCallStateChanged(:final state):
        if (state == GroupCallState.ended) {
          _callState = LatticeCallState.idle;
          _activeGroupCall = null;
          unawaited(_callEventSub?.cancel());
          _callEventSub = null;
        }
      case GroupCallStateError():
        _callState = LatticeCallState.failed;
      case ParticipantsJoinEvent() ||
            ParticipantsLeftEvent() ||
            CallReactionAddedEvent() ||
            CallReactionRemovedEvent() ||
            GroupCallActiveSpeakerChanged() ||
            CallAddedEvent() ||
            CallRemovedEvent() ||
            CallReplacedEvent() ||
            GroupCallStreamAdded() ||
            GroupCallStreamRemoved() ||
            GroupCallStreamReplaced() ||
            GroupCallLocalScreenshareStateChanged() ||
            GroupCallLocalMutedChanged():
        break;
    }
    notifyListeners();
  }
}

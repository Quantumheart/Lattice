import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:matrix/matrix.dart';

mixin CallActionsMixin on ChangeNotifier {
  // ── Cross-mixin dependencies ──────────────────────────────────
  Client get client;
  LatticeCallState get callState;
  @protected
  set callState(LatticeCallState value);
  String? get activeCallRoomId;
  @protected
  set activeCallRoomId(String? value);
  DateTime? get callStartTime;
  @protected
  set callStartTime(DateTime? value);
  bool get initialized;
  void init();
  void stopRinging();
  String? get cachedLivekitServiceUrl;
  Future<void> fetchWellKnownLiveKit();
  Future<void> sendMembershipEvent(String roomId, String livekitAlias);
  void startMembershipRenewal(String roomId, String livekitAlias);
  void cancelMembershipRenewal();
  Future<void> removeMembershipEvent(String roomId);
  Future<void> connectLiveKit({
    required String livekitServiceUrl,
    required String livekitAlias,
  });
  Future<void> cleanupLiveKit();
  String? get activeCallId;
  Future<void> sendCallHangup(String roomId, String callId, {String reason});

  // ── Teardown ─────────────────────────────────────────────────
  Future<void> _teardownCall({String? roomId}) async {
    await cleanupLiveKit();
    cancelMembershipRenewal();
    if (roomId != null) {
      try {
        await removeMembershipEvent(roomId);
      } catch (e) {
        debugPrint('[Lattice] Error removing membership: $e');
      }
    }
    activeCallRoomId = null;
    callStartTime = null;
  }

  // ── Join / Leave ──────────────────────────────────────────────

  bool _canJoin(String roomId) {
    if (!initialized) init();
    final allowed = CallService.validTransitions[callState];
    if (allowed == null || !allowed.contains(LatticeCallState.joining)) {
      return false;
    }
    if (client.getRoomById(roomId) == null) return false;
    return true;
  }

  Future<void> _connectToLiveKit(String roomId, Room room) async {
    if (cachedLivekitServiceUrl == null) {
      await fetchWellKnownLiveKit();
    }
    final livekitServiceUrl = cachedLivekitServiceUrl;
    if (livekitServiceUrl == null) {
      throw Exception('LiveKit service URL not found in well-known');
    }

    final livekitAlias =
        room.canonicalAlias.isNotEmpty ? room.canonicalAlias : room.id;

    activeCallRoomId = roomId;

    await sendMembershipEvent(roomId, livekitAlias);
    startMembershipRenewal(roomId, livekitAlias);

    await connectLiveKit(
      livekitServiceUrl: livekitServiceUrl,
      livekitAlias: livekitAlias,
    );
  }

  Future<void> joinCall(String roomId) async {
    if (!_canJoin(roomId)) return;

    final room = client.getRoomById(roomId)!;
    callState = LatticeCallState.joining;

    try {
      await _connectToLiveKit(roomId, room);
      stopRinging();

      if (callState != LatticeCallState.joining) {
        debugPrint('[Lattice] Call interrupted while joining, cleaning up');
        await _teardownCall(roomId: roomId);
        return;
      }

      callStartTime = DateTime.now();
      callState = LatticeCallState.connected;
      debugPrint('[Lattice] Joined call in room $roomId');
    } catch (e) {
      debugPrint('[Lattice] Failed to join call: $e');
      await _teardownCall(roomId: activeCallRoomId);
      stopRinging();
      if (callState == LatticeCallState.joining) {
        callState = LatticeCallState.failed;
      }
    }
  }

  Future<void> leaveCall() async {
    if (callState == LatticeCallState.joining) {
      callState = LatticeCallState.idle;
      return;
    }

    if (activeCallRoomId == null) {
      if (callState != LatticeCallState.idle) {
        callState = LatticeCallState.idle;
      }
      return;
    }

    final roomId = activeCallRoomId!;
    debugPrint('[Lattice] Leaving call in room $roomId');

    final callId = activeCallId;
    final room = client.getRoomById(roomId);
    if (callId != null && room != null && room.isDirectChat) {
      unawaited(sendCallHangup(roomId, callId));
    }

    stopRinging();
    callState = LatticeCallState.disconnecting;

    await _teardownCall(roomId: roomId);
    callState = LatticeCallState.idle;
  }

  // ── Queries ───────────────────────────────────────────────────
  bool roomHasActiveCall(String roomId) {
    final room = client.getRoomById(roomId);
    if (room == null) return false;
    return _getActiveRtcMemberships(room).isNotEmpty;
  }

  List<String> activeCallIdsForRoom(String roomId) {
    final room = client.getRoomById(roomId);
    if (room == null) return const [];
    final memberships = _getActiveRtcMemberships(room);
    final callIds = <String>{};
    for (final mem in memberships) {
      final callId = mem['call_id'] as String? ?? '';
      callIds.add(callId);
    }
    return callIds.toList();
  }

  int callParticipantCount(String roomId, String groupCallId) {
    final room = client.getRoomById(roomId);
    if (room == null) return 0;
    final memberships = _getActiveRtcMemberships(room);
    return memberships
        .where((m) => (m['call_id'] as String? ?? '') == groupCallId)
        .length;
  }

  List<Map<String, dynamic>> _getActiveRtcMemberships(Room room) {
    final states = room.states[callMemberEventType];
    if (states == null) return const [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <Map<String, dynamic>>[];

    for (final stateEvent in states.values) {
      final content = stateEvent.content;
      if (content.isEmpty) continue;

      final originTs = stateEvent is Event
          ? stateEvent.originServerTs.millisecondsSinceEpoch
          : now;

      final memberships = content['memberships'];
      if (memberships is List) {
        for (final mem in memberships) {
          if (mem is Map<String, dynamic> &&
              _isMembershipActive(mem, originTs, now)) {
            result.add(mem);
          }
        }
      } else {
        if (_isMembershipActive(content, originTs, now)) {
          result.add(Map<String, dynamic>.from(content));
        }
      }
    }
    return result;
  }

  bool _isMembershipActive(Map<String, dynamic> mem, int originTs, int nowMs) {
    final expiresTs = mem['expires_ts'] as int?;
    if (expiresTs != null) return expiresTs > nowMs;

    final expires = mem['expires'] as int?;
    if (expires != null) return (originTs + expires) > nowMs;

    return false;
  }
}

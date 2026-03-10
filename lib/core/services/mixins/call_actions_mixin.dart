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
  bool get joining;
  @protected
  set joining(bool value);
  bool get endedDuringJoin;
  @protected
  set endedDuringJoin(bool value);
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

  // ── Join / Leave ──────────────────────────────────────────────
  Future<void> joinCall(String roomId) async {
    if (!initialized) init();

    const allowedStates = {
      LatticeCallState.idle,
      LatticeCallState.joining,
      LatticeCallState.ringingOutgoing,
      LatticeCallState.failed,
    };
    if (joining) return;
    if (!allowedStates.contains(callState)) {
      if (callState != LatticeCallState.idle) {
        stopRinging();
        callState = LatticeCallState.failed;
        notifyListeners();
      }
      return;
    }

    final room = client.getRoomById(roomId);
    if (room == null) {
      if (callState == LatticeCallState.ringingOutgoing ||
          callState == LatticeCallState.joining) {
        stopRinging();
        callState = LatticeCallState.failed;
        notifyListeners();
      }
      return;
    }

    joining = true;
    if (callState != LatticeCallState.ringingOutgoing) {
      callState = LatticeCallState.joining;
    }
    notifyListeners();

    try {
      if (cachedLivekitServiceUrl == null) {
        await fetchWellKnownLiveKit();
      }
      final livekitServiceUrl = cachedLivekitServiceUrl;
      if (livekitServiceUrl == null) {
        throw Exception('LiveKit service URL not found in well-known');
      }

      final livekitAlias = room.canonicalAlias.isNotEmpty
          ? room.canonicalAlias
          : room.id;

      activeCallRoomId = roomId;

      await sendMembershipEvent(roomId, livekitAlias);
      startMembershipRenewal(roomId, livekitAlias);

      await connectLiveKit(
        livekitServiceUrl: livekitServiceUrl,
        livekitAlias: livekitAlias,
      );

      stopRinging();

      if (endedDuringJoin) {
        debugPrint('[Lattice] Call ended while joining, cleaning up');
        await cleanupLiveKit();
        await removeMembershipEvent(roomId);
        cancelMembershipRenewal();
        activeCallRoomId = null;
        callState = LatticeCallState.idle;
        notifyListeners();
        return;
      }

      callStartTime = DateTime.now();
      callState = LatticeCallState.connected;
      notifyListeners();
      debugPrint('[Lattice] Joined call in room $roomId');
    } catch (e) {
      debugPrint('[Lattice] Failed to join call: $e');
      await cleanupLiveKit();

      if (activeCallRoomId != null) {
        try {
          await removeMembershipEvent(activeCallRoomId!);
        } catch (leaveError) {
          debugPrint('[Lattice] Error removing membership after failure: $leaveError');
        }
      }

      cancelMembershipRenewal();
      activeCallRoomId = null;
      stopRinging();

      callState = LatticeCallState.failed;
      notifyListeners();
    } finally {
      joining = false;
      endedDuringJoin = false;
    }
  }

  Future<void> leaveCall() async {
    if (activeCallRoomId == null) return;

    final roomId = activeCallRoomId!;
    debugPrint('[Lattice] Leaving call in room $roomId');

    stopRinging();
    callState = LatticeCallState.disconnecting;
    notifyListeners();

    await cleanupLiveKit();
    cancelMembershipRenewal();

    try {
      await removeMembershipEvent(roomId);
    } catch (e) {
      debugPrint('[Lattice] Error removing membership: $e');
    }

    activeCallRoomId = null;
    callStartTime = null;
    callState = LatticeCallState.idle;
    notifyListeners();
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

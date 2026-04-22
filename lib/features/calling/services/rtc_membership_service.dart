import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:matrix/matrix.dart';

// ── Constants ──────────────────────────────────────────────

const callMemberEventType = 'org.matrix.msc3401.call.member';
const membershipExpiresMs = 14400000;
const membershipRenewalInterval = Duration(minutes: 5);

// ── RTC Membership Service ─────────────────────────────────

class RtcMembershipService {
  RtcMembershipService({required Client client}) : _client = client;

  Client _client;

  void updateClient(Client client) => _client = client;

  Timer? _membershipRenewalTimer;

  String get membershipStateKey =>
      '_${_client.userID!}_${_client.deviceID!}_m.call';

  Map<String, dynamic> makeMembershipContent(
    String livekitServiceUrl,
    String livekitAlias, {
    bool isVideo = false,
    int expiresMs = membershipExpiresMs,
  }) => {
    'application': 'm.call',
    'call_id': '',
    'scope': 'm.room',
    'device_id': _client.deviceID,
    'expires': expiresMs,
    kIoKoheraIsVideo: isVideo,
    'focus_active': {
      'type': 'livekit',
      'focus_selection': 'oldest_membership',
    },
    'foci_preferred': [
      {
        'type': 'livekit',
        'livekit_service_url': livekitServiceUrl,
        'livekit_alias': livekitAlias,
      },
    ],
  };

  Future<void> sendMembershipEvent(
    String roomId,
    String livekitAlias, {
    required String livekitServiceUrl,
    bool isVideo = false,
    int expiresMs = membershipExpiresMs,
  }) async {
    await _client.setRoomStateWithKey(
      roomId,
      callMemberEventType,
      membershipStateKey,
      makeMembershipContent(
        livekitServiceUrl,
        livekitAlias,
        isVideo: isVideo,
        expiresMs: expiresMs,
      ),
    );
  }

  Future<void> removeMembershipEvent(String roomId) async {
    await _client.setRoomStateWithKey(
      roomId,
      callMemberEventType,
      membershipStateKey,
      {},
    );
  }

  void startMembershipRenewal(
    String roomId,
    String livekitAlias, {
    required String livekitServiceUrl,
    bool isVideo = false,
  }) {
    cancelMembershipRenewal();
    _membershipRenewalTimer = Timer.periodic(
      membershipRenewalInterval,
      (_) => sendMembershipEvent(
        roomId,
        livekitAlias,
        livekitServiceUrl: livekitServiceUrl,
        isVideo: isVideo,
      ).catchError(
        (Object e) => debugPrint('[Kohera] Failed to renew membership: $e'),
      ),
    );
  }

  void cancelMembershipRenewal() {
    _membershipRenewalTimer?.cancel();
    _membershipRenewalTimer = null;
  }

  // ── Membership Queries ──────────────────────────────────────

  static bool roomHasActiveCall(Client client, String roomId) {
    final room = client.getRoomById(roomId);
    if (room == null) return false;
    return _getActiveRtcMemberships(room).isNotEmpty;
  }

  static bool roomHasRemoteActiveCall(Client client, String roomId) {
    final room = client.getRoomById(roomId);
    if (room == null) return false;
    final states = room.states[callMemberEventType];
    if (states == null) return false;
    final localPrefix = '_${client.userID!}_';
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in states.entries) {
      if (entry.key.startsWith(localPrefix)) continue;
      final content = entry.value.content;
      if (content.isEmpty) continue;
      final originTs = entry.value is Event
          ? (entry.value as Event).originServerTs.millisecondsSinceEpoch
          : now;
      if (_isMembershipActive(content, originTs, now)) return true;
    }
    return false;
  }

  static final _stateKeyUserIdRegex = RegExp('_(@[^:]+:[^_]+)_');

  static String? userIdFromStateKey(String stateKey) =>
      _stateKeyUserIdRegex.firstMatch(stateKey)?.group(1);

  static Set<String> activeCallParticipantUserIds(
    Client client,
    String roomId,
  ) {
    final room = client.getRoomById(roomId);
    if (room == null) return const {};
    final states = room.states[callMemberEventType];
    if (states == null) return const {};

    final now = DateTime.now().millisecondsSinceEpoch;
    final userIds = <String>{};

    for (final entry in states.entries) {
      final content = entry.value.content;
      if (content.isEmpty) continue;
      final originTs = entry.value is Event
          ? (entry.value as Event).originServerTs.millisecondsSinceEpoch
          : now;

      final memberships = content['memberships'];
      bool hasActive;
      if (memberships is List) {
        hasActive = memberships.any(
          (m) =>
              m is Map<String, dynamic> &&
              _isMembershipActive(m, originTs, now),
        );
      } else {
        hasActive = _isMembershipActive(content, originTs, now);
      }

      if (hasActive) {
        final match = _stateKeyUserIdRegex.firstMatch(entry.key);
        if (match != null) userIds.add(match.group(1)!);
      }
    }
    return userIds;
  }

  static List<String> activeCallIdsForRoom(Client client, String roomId) {
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

  static int callParticipantCount(
    Client client,
    String roomId,
    String groupCallId,
  ) {
    final room = client.getRoomById(roomId);
    if (room == null) return 0;
    final memberships = _getActiveRtcMemberships(room);
    return memberships
        .where((m) => (m['call_id'] as String? ?? '') == groupCallId)
        .length;
  }

  static List<Map<String, dynamic>> _getActiveRtcMemberships(Room room) {
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

  static bool _isMembershipActive(
    Map<String, dynamic> mem,
    int originTs,
    int nowMs,
  ) {
    final expiresTs = mem['expires_ts'] as int?;
    if (expiresTs != null) return expiresTs > nowMs;

    final expires = mem['expires'] as int?;
    if (expires != null) return (originTs + expires) > nowMs;

    return false;
  }
}

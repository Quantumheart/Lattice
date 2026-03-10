import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:matrix/matrix.dart';

mixin CallRtcMembershipMixin on ChangeNotifier {
  // ── Cross-mixin dependencies ──────────────────────────────────
  Client get client;
  String? get activeCallRoomId;
  String? get cachedLivekitServiceUrl;

  // ── State ─────────────────────────────────────────────────────
  Timer? _membershipRenewalTimer;

  // ── Membership State Key ──────────────────────────────────────
  String get membershipStateKey =>
      '_${client.userID!}_${client.deviceID!}_m.call';

  Map<String, dynamic> makeMembershipContent(
    String livekitServiceUrl,
    String livekitAlias,
  ) => {
    'application': 'm.call',
    'call_id': '',
    'scope': 'm.room',
    'device_id': client.deviceID,
    'expires': membershipExpiresMs,
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

  // ── Send / Remove ─────────────────────────────────────────────
  @protected
  Future<void> sendMembershipEvent(String roomId, String livekitAlias) async {
    await client.setRoomStateWithKey(
      roomId,
      callMemberEventType,
      membershipStateKey,
      makeMembershipContent(cachedLivekitServiceUrl!, livekitAlias),
    );
  }

  @protected
  Future<void> removeMembershipEvent(String roomId) async {
    await client.setRoomStateWithKey(
      roomId,
      callMemberEventType,
      membershipStateKey,
      {},
    );
  }

  // ── Renewal ───────────────────────────────────────────────────
  @protected
  void startMembershipRenewal(String roomId, String livekitAlias) {
    cancelMembershipRenewal();
    _membershipRenewalTimer = Timer.periodic(
      membershipRenewalInterval,
      (_) => sendMembershipEvent(roomId, livekitAlias).catchError(
        (Object e) => debugPrint('[Lattice] Failed to renew membership: $e'),
      ),
    );
  }

  @protected
  void cancelMembershipRenewal() {
    _membershipRenewalTimer?.cancel();
    _membershipRenewalTimer = null;
  }
}

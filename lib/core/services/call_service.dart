import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/core/services/mixins/call_actions_mixin.dart';
import 'package:lattice/core/services/mixins/call_livekit_mixin.dart';
import 'package:lattice/core/services/mixins/call_ringing_mixin.dart';
import 'package:lattice/core/services/mixins/call_rtc_membership_mixin.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';

// ── Call State ──────────────────────────────────────────────

enum LatticeCallState {
  idle,
  ringingOutgoing,
  ringingIncoming,
  joining,
  connected,
  reconnecting,
  disconnecting,
  failed,
}

// ── Types ──────────────────────────────────────────────────

typedef LiveKitRoomFactory = livekit.Room Function();
typedef HttpPostFunction = Future<http.Response> Function(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
});

// ── Constants ──────────────────────────────────────────────

const callMemberEventType = 'org.matrix.msc3401.call.member';
const membershipExpiresMs = 14400000;
const membershipRenewalInterval = Duration(minutes: 5);

// ── Call Service ────────────────────────────────────────────

class CallService extends ChangeNotifier
    with CallRtcMembershipMixin, CallLiveKitMixin, CallRingingMixin, CallActionsMixin {
  CallService({required Client client}) : _client = client;

  Client _client;

  @override
  Client get client => _client;

  bool _disposed = false;
  bool _initialized = false;

  @override
  bool get initialized => _initialized;

  // ── Shared State ─────────────────────────────────────────────

  LatticeCallState _callState = LatticeCallState.idle;

  @override
  LatticeCallState get callState => _callState;

  @override
  @protected
  set callState(LatticeCallState value) => _callState = value;

  String? _activeCallRoomId;

  @override
  String? get activeCallRoomId => _activeCallRoomId;

  @override
  @protected
  set activeCallRoomId(String? value) => _activeCallRoomId = value;

  bool _joining = false;

  @override
  bool get joining => _joining;

  @override
  @protected
  set joining(bool value) => _joining = value;

  @visibleForTesting
  bool get isJoining => _joining;

  bool _endedDuringJoin = false;

  @override
  bool get endedDuringJoin => _endedDuringJoin;

  @override
  @protected
  set endedDuringJoin(bool value) => _endedDuringJoin = value;

  DateTime? _callStartTime;

  @override
  DateTime? get callStartTime => _callStartTime;

  @override
  @protected
  set callStartTime(DateTime? value) => _callStartTime = value;

  Duration? get callElapsed =>
      _callStartTime != null ? DateTime.now().difference(_callStartTime!) : null;

  // ── Lifecycle ────────────────────────────────────────────────

  @override
  void init() {
    if (_initialized) return;
    _initialized = true;
    unawaited(fetchWellKnownLiveKit());
    debugPrint('[Lattice] CallService initialized');
  }

  void _resetState() {
    unawaited(cleanupLiveKit());
    cancelMembershipRenewal();
    _activeCallRoomId = null;
    _callState = LatticeCallState.idle;
    _initialized = false;
    resetIncomingCall();
    stopRinging();
    disposeRingtone();
    _callStartTime = null;
  }

  void updateClient(Client newClient) {
    if (identical(_client, newClient)) return;
    _resetState();
    _client = newClient;
  }

  @override
  void dispose() {
    _disposed = true;
    _resetState();
    closeIncomingCallController();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}

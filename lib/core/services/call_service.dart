import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/core/services/mixins/call_actions_mixin.dart';
import 'package:lattice/core/services/mixins/call_livekit_mixin.dart';
import 'package:lattice/core/services/mixins/call_native_ui_mixin.dart';
import 'package:lattice/core/services/mixins/call_ringing_mixin.dart';
import 'package:lattice/core/services/mixins/call_rtc_membership_mixin.dart';
import 'package:lattice/core/services/mixins/call_signaling_mixin.dart';
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
  http.Client httpClient,
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
    with
        CallRtcMembershipMixin,
        CallLiveKitMixin,
        CallRingingMixin,
        CallActionsMixin,
        CallSignalingMixin,
        CallNativeUiMixin {
  CallService({required Client client}) : _client = client;

  Client _client;

  @override
  Client get client => _client;

  bool _disposed = false;
  bool _initialized = false;

  @override
  bool get initialized => _initialized;

  // ── Shared State ─────────────────────────────────────────────

  static const Map<LatticeCallState, Set<LatticeCallState>> validTransitions = {
    LatticeCallState.idle: {
      LatticeCallState.joining,
      LatticeCallState.ringingOutgoing,
      LatticeCallState.ringingIncoming,
    },
    LatticeCallState.ringingOutgoing: {
      LatticeCallState.joining,
      LatticeCallState.connected,
      LatticeCallState.idle,
      LatticeCallState.failed,
    },
    LatticeCallState.ringingIncoming: {
      LatticeCallState.joining,
      LatticeCallState.idle,
    },
    LatticeCallState.joining: {
      LatticeCallState.connected,
      LatticeCallState.idle,
      LatticeCallState.failed,
    },
    LatticeCallState.connected: {
      LatticeCallState.reconnecting,
      LatticeCallState.disconnecting,
      LatticeCallState.failed,
    },
    LatticeCallState.reconnecting: {
      LatticeCallState.connected,
      LatticeCallState.disconnecting,
      LatticeCallState.failed,
    },
    LatticeCallState.disconnecting: {
      LatticeCallState.idle,
    },
    LatticeCallState.failed: {
      LatticeCallState.idle,
      LatticeCallState.joining,
      LatticeCallState.ringingOutgoing,
    },
  };

  LatticeCallState _callState = LatticeCallState.idle;

  @override
  LatticeCallState get callState => _callState;

  @override
  @protected
  set callState(LatticeCallState next) {
    if (_callState == next) return;
    final allowed = validTransitions[_callState];
    if (allowed == null || !allowed.contains(next)) {
      debugPrint(
        '[Lattice] Invalid call state transition: $_callState → $next',
      );
      assert(false, 'Invalid call state transition: $_callState → $next');
      return;
    }
    _callState = next;
    notifyListeners();
    switch (next) {
      case LatticeCallState.connected:
        updateNativeCallConnected();
      case LatticeCallState.idle:
      case LatticeCallState.disconnecting:
      case LatticeCallState.failed:
        endNativeCall();
      default:
        break;
    }
  }

  String? _activeCallRoomId;

  @override
  String? get activeCallRoomId => _activeCallRoomId;

  @override
  @protected
  set activeCallRoomId(String? value) => _activeCallRoomId = value;

  DateTime? _callStartTime;

  @override
  DateTime? get callStartTime => _callStartTime;

  @override
  @protected
  set callStartTime(DateTime? value) => _callStartTime = value;

  Duration? get callElapsed => _callStartTime != null
      ? DateTime.now().difference(_callStartTime!)
      : null;

  // ── Lifecycle ────────────────────────────────────────────────

  @override
  void init() {
    if (_initialized) return;
    _initialized = true;
    unawaited(fetchWellKnownLiveKit());
    startSignalingListener();
    initNativeCallUi();
    debugPrint('[Lattice] CallService initialized');
  }

  void _resetState() {
    endNativeCall();
    stopSignalingListener();
    unawaited(cleanupLiveKit());
    cancelMembershipRenewal();
    _activeCallRoomId = null;
    _callState = LatticeCallState.idle;
    _initialized = false;
    resetIncomingCall();
    stopRinging();
    disposeRingtone();
    clearActiveCallId();
    _callStartTime = null;
  }

  void updateClient(Client newClient) {
    if (identical(_client, newClient)) return;
    _resetState();
    _client = newClient;
  }

  @override
  void dispose() {
    disposeNativeCallUi();
    _resetState();
    closeIncomingCallController();
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}

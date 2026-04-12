import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/utils/platform_info.dart';
import 'package:lattice/features/calling/models/call_participant.dart' as ui;
import 'package:lattice/features/calling/models/call_state.dart';
import 'package:lattice/features/calling/models/incoming_call_info.dart' as model;
import 'package:lattice/features/calling/services/call_ringing_service.dart';
import 'package:lattice/features/calling/services/call_signaling_service.dart';
import 'package:lattice/features/calling/services/livekit_service.dart';
import 'package:lattice/features/calling/services/native_call_ui_service.dart';
import 'package:lattice/features/calling/services/ringtone_service.dart';
import 'package:lattice/features/calling/services/rtc_membership_service.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';

export 'package:lattice/features/calling/models/call_state.dart';
export 'package:lattice/features/calling/services/livekit_service.dart'
    show HttpPostFunction, LiveKitRoomFactory;
export 'package:lattice/features/calling/services/rtc_membership_service.dart'
    show callMemberEventType, membershipExpiresMs, membershipRenewalInterval;

// ── Call Service ────────────────────────────────────────────

class CallService extends ChangeNotifier with WidgetsBindingObserver {
  CallService({
    required Client client,
    RingtoneService? ringtoneService,
  }) : _client = client {
    _rtcMembership = RtcMembershipService(client: client);
    _liveKit = LiveKitService(
      client: client,
      onChanged: notifyListeners,
    );
    _signaling = CallSignalingService(client: client);
    _ringing = CallRingingService(ringtoneService: ringtoneService);
    _nativeUi = NativeCallUiService();
  }

  Client _client;
  Client get client => _client;

  PreferencesService? _prefs;
  set preferencesService(PreferencesService? prefs) => _prefs = prefs;

  bool _disposed = false;
  bool _initialized = false;
  bool get initialized => _initialized;

  // ── Sub-services ───────────────────────────────────────────

  late final RtcMembershipService _rtcMembership;
  late final LiveKitService _liveKit;
  late final CallSignalingService _signaling;
  late final CallRingingService _ringing;
  late final NativeCallUiService _nativeUi;

  StreamSubscription<SignalingEvent>? _signalingEventSub;
  StreamSubscription<NativeCallAction>? _nativeActionSub;
  StreamSubscription<LiveKitConnectionEvent>? _liveKitConnectionSub;
  StreamSubscription<({String roomId, StrippedStateEvent state})>?
      _membershipWatcherSub;

  // ── Ringtone Injection ─────────────────────────────────────

  set ringtoneService(RingtoneService? service) =>
      _ringing.ringtoneService = service;

  // ── Test Accessors ─────────────────────────────────────────

  @visibleForTesting
  set roomFactoryForTest(LiveKitRoomFactory factory) =>
      _liveKit.roomFactoryForTest = factory;

  @visibleForTesting
  HttpPostFunction get httpPostForTest => _liveKit.httpPostForTest;

  @visibleForTesting
  set httpPostForTest(HttpPostFunction fn) {
    _liveKit.httpPostForTest = fn;
  }

  @visibleForTesting
  set cachedLivekitServiceUrlForTest(String? url) =>
      _liveKit.cachedLivekitServiceUrlForTest = url;

  @visibleForTesting
  void simulateCallEnded() => _handleCallEnded();

  // ── Delegated Getters ──────────────────────────────────────

  livekit.Room? get livekitRoom => _liveKit.livekitRoom;
  List<livekit.RemoteParticipant> get participants => _liveKit.participants;
  bool get isMicEnabled => _liveKit.isMicEnabled;
  bool get isCameraEnabled => _liveKit.isCameraEnabled;
  bool get isScreenShareEnabled => _liveKit.isScreenShareEnabled;
  List<livekit.Participant> get activeSpeakers => _liveKit.activeSpeakers;
  String? get cachedLivekitServiceUrl => _liveKit.cachedLivekitServiceUrl;
  bool get isCallingAvailable => _liveKit.cachedLivekitServiceUrl != null;

  List<ui.CallParticipant> get allParticipants =>
      _liveKit.allParticipants(activeCallRoomId: _activeCallRoomId);

  Future<void> toggleMicrophone() => _liveKit.toggleMicrophone();
  Future<void> toggleCamera() => _liveKit.toggleCamera();
  Future<void> toggleScreenShare({String? sourceId}) =>
      _liveKit.toggleScreenShare(sourceId: sourceId);
  Future<void> setOutputVolume(double volume) =>
      _liveKit.setOutputVolume(volume);

  bool get isSpeakerOn => livekit.Hardware.instance.speakerOn ?? true;
  Future<void> toggleSpeaker() async {
    final current = isSpeakerOn;
    await livekit.Hardware.instance.setSpeakerphoneOn(!current);
    notifyListeners();
  }

  model.IncomingCallInfo? get incomingCall => _ringing.incomingCall;
  Stream<model.IncomingCallInfo> get incomingCallStream =>
      _ringing.incomingCallStream;

  Stream<String> get nativeAcceptedCallStream =>
      _nativeUi.nativeAcceptedCallStream;

  String? get activeCallId => _activeCallId;

  // ── Shared State ───────────────────────────────────────────

  LatticeCallState _callState = LatticeCallState.idle;
  LatticeCallState get callState => _callState;

  void _setCallState(LatticeCallState next) {
    if (_callState == next) return;
    final allowed = validCallTransitions[_callState];
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
        _nativeUi.updateNativeCallConnected();
      case LatticeCallState.idle:
      case LatticeCallState.disconnecting:
      case LatticeCallState.failed:
        _nativeUi.endNativeCall();
      default:
        break;
    }
  }

  String? _activeCallRoomId;
  String? get activeCallRoomId => _activeCallRoomId;

  DateTime? _callStartTime;
  DateTime? get callStartTime => _callStartTime;

  Duration? get callElapsed => _callStartTime != null
      ? DateTime.now().difference(_callStartTime!)
      : null;

  String? _activeCallId;
  String? _lastInitiatedRoomId;
  bool _hadRemoteParticipant = false;

  // ── Membership Watcher ──────────────────────────────────────

  void _startMembershipWatcher(String roomId) {
    _stopMembershipWatcher();
    _membershipWatcherSub = _client.onRoomState.stream.listen((update) {
      if (update.roomId != roomId) return;
      if (update.state.type != callMemberEventType) return;
      _onMembershipChanged(roomId);
    });
  }

  void _onMembershipChanged(String roomId) {
    final hasRemote =
        RtcMembershipService.roomHasRemoteActiveCall(_client, roomId);

    if (_callState == LatticeCallState.ringingOutgoing && hasRemote) {
      debugPrint('[Lattice] Detected RTC membership join, treating as answer');
      unawaited(joinCall(roomId));
      return;
    }

    if (hasRemote) {
      _hadRemoteParticipant = true;
    }

    final isDm = _client.getRoomById(roomId)?.isDirectChat ?? false;
    if (isDm &&
        (_callState == LatticeCallState.connected ||
            _callState == LatticeCallState.reconnecting) &&
        !hasRemote &&
        _hadRemoteParticipant) {
      debugPrint('[Lattice] DM remote member left, ending call');
      unawaited(leaveCall());
      return;
    }

    notifyListeners();
  }

  void _stopMembershipWatcher() {
    unawaited(_membershipWatcherSub?.cancel());
    _membershipWatcherSub = null;
  }

  // ── Lifecycle ──────────────────────────────────────────────

  void init() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_liveKit.fetchWellKnownLiveKit());
    _signaling.startSignalingListener(
      getActiveCallId: () => _activeCallId,
      getCallState: () => _callState.name,
    );
    _nativeUi.init(getCallState: () => _callState.name);

    _signalingEventSub = _signaling.events.listen(_onSignalingEvent);
    _nativeActionSub = _nativeUi.actions.listen(_onNativeAction);
    _liveKitConnectionSub = _liveKit.connectionEvents.listen(_onLiveKitConnection);

    debugPrint('[Lattice] CallService initialized');
  }

  void _resetState() {
    _nativeUi.endNativeCall();
    _signaling.stopSignalingListener();
    unawaited(_liveKit.cleanupLiveKit());
    _rtcMembership.cancelMembershipRenewal();
    _activeCallRoomId = null;
    _callState = LatticeCallState.idle;
    _initialized = false;
    _ringing.resetIncomingCall();
    _ringing.stopRinging();
    _ringing.disposeRingtone();
    _activeCallId = null;
    _callStartTime = null;
    _hadRemoteParticipant = false;
    unawaited(_signalingEventSub?.cancel());
    _signalingEventSub = null;
    unawaited(_nativeActionSub?.cancel());
    _nativeActionSub = null;
    unawaited(_liveKitConnectionSub?.cancel());
    _liveKitConnectionSub = null;
    _stopMembershipWatcher();
  }

  void updateClient(Client newClient) {
    if (identical(_client, newClient)) return;
    _resetState();
    _client = newClient;
    _rtcMembership.updateClient(newClient);
    _liveKit.updateClient(newClient);
    _signaling.updateClient(newClient);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _callState == LatticeCallState.connected &&
        _activeCallRoomId != null &&
        _liveKit.isScreenShareEnabled) {
      if (isNativeMobile) {
        unawaited(toggleScreenShare());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativeUi.dispose();
    _resetState();
    _ringing.dispose();
    _liveKit.dispose();
    _signaling.dispose();
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ── Teardown ───────────────────────────────────────────────

  Future<void> _teardownCall({String? roomId}) async {
    await _liveKit.cleanupLiveKit();
    _rtcMembership.cancelMembershipRenewal();
    if (roomId != null) {
      try {
        await _rtcMembership.removeMembershipEvent(roomId);
      } catch (e) {
        debugPrint('[Lattice] Error removing membership: $e');
      }
    }
    _activeCallRoomId = null;
    _callStartTime = null;
    _hadRemoteParticipant = false;
  }

  // ── Join / Leave ───────────────────────────────────────────

  bool _canJoin(String roomId) {
    if (!_initialized) init();
    final allowed = validCallTransitions[_callState];
    if (allowed == null || !allowed.contains(LatticeCallState.joining)) {
      return false;
    }
    if (_client.getRoomById(roomId) == null) return false;
    return true;
  }

  Future<void> _connectToLiveKit(String roomId, Room room) async {
    if (_liveKit.cachedLivekitServiceUrl == null) {
      await _liveKit.fetchWellKnownLiveKit();
    }
    final livekitServiceUrl = _liveKit.cachedLivekitServiceUrl;
    if (livekitServiceUrl == null) {
      throw Exception('LiveKit service URL not found in well-known');
    }

    final livekitAlias =
        room.canonicalAlias.isNotEmpty ? room.canonicalAlias : room.id;

    _activeCallRoomId = roomId;

    await _rtcMembership.sendMembershipEvent(
      roomId,
      livekitAlias,
      livekitServiceUrl: livekitServiceUrl,
    );
    _rtcMembership.startMembershipRenewal(
      roomId,
      livekitAlias,
      livekitServiceUrl: livekitServiceUrl,
    );

    await _liveKit.connectLiveKit(
      livekitServiceUrl: livekitServiceUrl,
      livekitAlias: livekitAlias,
      currentState: () => _callState,
      autoMuteOnJoin: _prefs?.autoMuteOnJoin ?? false,
      noiseSuppression: _prefs?.noiseSuppression ?? true,
      echoCancellation: _prefs?.echoCancellation ?? true,
      autoGainControl: _prefs?.autoGainControl ?? true,
      voiceIsolation: _prefs?.voiceIsolation ?? true,
      typingNoiseDetection: _prefs?.typingNoiseDetection ?? true,
      highPassFilter: _prefs?.highPassFilter ?? false,
      audioEncoding: _audioEncodingFromQuality(_prefs?.audioQuality),
      inputDeviceId: _prefs?.inputDeviceId,
      outputDeviceId: _prefs?.outputDeviceId,
      inputVolume: _prefs?.inputVolume ?? 1.0,
      outputVolume: _prefs?.outputVolume ?? 1.0,
    );
  }

  static livekit.AudioEncoding? _audioEncodingFromQuality(
    AudioQuality? quality,
  ) =>
      switch (quality) {
        AudioQuality.speech => livekit.AudioEncoding.presetSpeech,
        AudioQuality.music => livekit.AudioEncoding.presetMusic,
        AudioQuality.high => livekit.AudioEncoding.presetMusicHighQuality,
        null => null,
      };

  Future<void> joinCall(String roomId) async {
    if (!_canJoin(roomId)) return;

    final room = _client.getRoomById(roomId)!;
    _setCallState(LatticeCallState.joining);

    try {
      await _connectToLiveKit(roomId, room);
      _ringing.stopRinging();

      if (_callState != LatticeCallState.joining) {
        debugPrint('[Lattice] Call interrupted while joining, cleaning up');
        await _teardownCall(roomId: roomId);
        return;
      }

      _callStartTime = DateTime.now();
      _startMembershipWatcher(roomId);
      _setCallState(LatticeCallState.connected);
      debugPrint('[Lattice] Joined call in room $roomId');
    } catch (e) {
      debugPrint('[Lattice] Failed to join call: $e');
      await _teardownCall(roomId: _activeCallRoomId);
      _ringing.stopRinging();
      if (_callState == LatticeCallState.joining) {
        _setCallState(LatticeCallState.failed);
      }
    }
  }

  Future<void> leaveCall() async {
    if (_callState == LatticeCallState.ringingOutgoing) {
      cancelOutgoingCall();
      return;
    }

    if (_callState == LatticeCallState.ringingIncoming) {
      declineCall();
      return;
    }

    if (_callState == LatticeCallState.joining) {
      await _teardownCall(roomId: _activeCallRoomId);
      _activeCallId = null;
      _lastInitiatedRoomId = null;
      _setCallState(LatticeCallState.idle);
      return;
    }

    if (_activeCallRoomId == null) {
      if (_callState != LatticeCallState.idle) {
        _setCallState(LatticeCallState.idle);
      }
      return;
    }

    final roomId = _activeCallRoomId!;
    debugPrint('[Lattice] Leaving call in room $roomId');
    _stopMembershipWatcher();

    final callId = _activeCallId;
    final room = _client.getRoomById(roomId);
    if (callId != null && room != null && room.isDirectChat) {
      unawaited(_signaling.sendCallHangup(roomId, callId));
    }

    _activeCallId = null;
    _lastInitiatedRoomId = null;
    _ringing.stopRinging();
    _setCallState(LatticeCallState.disconnecting);

    await _teardownCall(roomId: roomId);
    _setCallState(LatticeCallState.idle);
  }

  // ── Ringing Actions ────────────────────────────────────────

  Future<void> acceptCall({bool withVideo = false}) async {
    if (_callState != LatticeCallState.ringingIncoming) return;
    final info = _ringing.incomingCall;
    if (info == null) return;

    _ringing.resetIncomingCall();
    _ringing.stopRinging();

    if (info.callId != null) {
      unawaited(_signaling.sendCallAnswer(info.roomId, info.callId!));
    }

    await joinCall(info.roomId);
  }

  void declineCall() {
    if (_callState != LatticeCallState.ringingIncoming) return;
    final info = _ringing.incomingCall;

    if (info?.callId != null) {
      unawaited(_signaling.sendCallReject(info!.roomId, info.callId!));
    }

    _ringing.stopRinging();
    _ringing.resetIncomingCall();
    _setCallState(LatticeCallState.idle);
  }

  void cancelOutgoingCall({bool isTimeout = false}) {
    if (_callState != LatticeCallState.ringingOutgoing &&
        _callState != LatticeCallState.joining) {
      return;
    }

    final callId = _activeCallId;
    if (callId != null && _lastInitiatedRoomId != null) {
      final reason = isTimeout ? 'invite_timeout' : 'user_hangup';
      unawaited(
        _signaling.sendCallHangup(_lastInitiatedRoomId!, callId, reason: reason),
      );
    }

    if (_callState == LatticeCallState.joining) {
      unawaited(_teardownCall(roomId: _activeCallRoomId));
    }

    _stopMembershipWatcher();
    _ringing.stopRinging();
    _activeCallId = null;
    _lastInitiatedRoomId = null;
    _setCallState(LatticeCallState.idle);
    _activeCallRoomId = null;
  }

  Future<void> initiateCall(
    String roomId, {
    model.CallType type = model.CallType.voice,
  }) async {
    if (!_initialized) init();
    if (_callState != LatticeCallState.idle &&
        _callState != LatticeCallState.failed) {
      return;
    }

    final callId = _signaling.generateCallId();
    _activeCallId = callId;
    _lastInitiatedRoomId = roomId;
    _activeCallRoomId = roomId;
    _setCallState(LatticeCallState.ringingOutgoing);

    final room = _client.getRoomById(roomId);
    final callerName = room?.getLocalizedDisplayname() ?? roomId;
    final isVideo = type == model.CallType.video;
    _nativeUi.showNativeOutgoingCall(roomId, callerName, isVideo);

    if (kIsWeb || isNativeDesktop) {
      _ringing.playDialtone();
    }

    _ringing.startRingingTimer(
      const Duration(seconds: 60),
      () => cancelOutgoingCall(isTimeout: true),
    );

    _startMembershipWatcher(roomId);

    await _signaling.sendCallInvite(
      roomId,
      callId,
      isVideo: type == model.CallType.video,
    );
  }

  // ── Queries ────────────────────────────────────────────────

  bool roomHasActiveCall(String roomId) =>
      RtcMembershipService.roomHasActiveCall(_client, roomId);

  List<String> activeCallIdsForRoom(String roomId) =>
      RtcMembershipService.activeCallIdsForRoom(_client, roomId);

  int callParticipantCount(String roomId, String groupCallId) =>
      RtcMembershipService.callParticipantCount(_client, roomId, groupCallId);

  Set<String> callParticipantUserIds(String roomId) =>
      RtcMembershipService.activeCallParticipantUserIds(_client, roomId);

  // ── Push Call Handling ─────────────────────────────────────

  void handlePushCallInvite({
    required String roomId,
    required String? callId,
    required String callerName,
    required bool isVideo,
  }) {
    if (!_initialized) init();
    _activeCallId = callId;
    final info = model.IncomingCallInfo(
      roomId: roomId,
      callId: callId,
      callerName: callerName,
      isVideo: isVideo,
    );
    _ringing.pushIncomingCall(info);
    _setCallState(LatticeCallState.ringingIncoming);
    _nativeUi.showNativeIncomingCall(
      callId: callId,
      roomId: roomId,
      callerName: callerName,
      callerAvatarUrl: null,
      isVideo: isVideo,
    );
    if (kIsWeb || isNativeDesktop) {
      _ringing.playRingtone();
    }
  }

  // ── Event Handlers ─────────────────────────────────────────

  void _onSignalingEvent(SignalingEvent event) {
    switch (event) {
      case IncomingInvite():
        _handleSignalingIncomingInvite(event);
      case AnswerReceived():
        _stopMembershipWatcher();
        unawaited(joinCall(event.roomId));
      case RejectReceived():
        _stopMembershipWatcher();
        _activeCallId = null;
        _activeCallRoomId = null;
        _lastInitiatedRoomId = null;
        _ringing.stopRinging();
        _setCallState(LatticeCallState.idle);
      case HangupReceived():
        _activeCallId = null;
        if (_callState == LatticeCallState.connected ||
            _callState == LatticeCallState.reconnecting) {
          unawaited(leaveCall());
        } else {
          _handleCallEnded();
        }
      case GlareResolved():
        _activeCallId = null;
        _activeCallRoomId = null;
        _lastInitiatedRoomId = null;
        _ringing.stopRinging();
        _setCallState(LatticeCallState.idle);
        _handleSignalingIncomingInvite(event.incomingInvite);
    }
  }

  void _handleSignalingIncomingInvite(IncomingInvite event) {
    _activeCallId = event.callId;
    _ringing.pushIncomingCall(event.info);
    _setCallState(LatticeCallState.ringingIncoming);
    _nativeUi.showNativeIncomingCall(
      callId: event.info.callId,
      roomId: event.info.roomId,
      callerName: event.info.callerName,
      callerAvatarUrl: event.info.callerAvatarUrl,
      isVideo: event.info.isVideo,
    );
    if (kIsWeb || isNativeDesktop) {
      _ringing.playRingtone();
    }
  }

  void _handleCallEnded() {
    _ringing.resetIncomingCall();
    _ringing.stopRinging();
    _activeCallRoomId = null;
    _lastInitiatedRoomId = null;
    if (_callState != LatticeCallState.idle &&
        _callState != LatticeCallState.disconnecting) {
      _setCallState(LatticeCallState.idle);
    }
  }

  void _onNativeAction(NativeCallAction action) {
    switch (action) {
      case NativeCallAccepted():
        unawaited(acceptCall(withVideo: action.withVideo));
      case NativeCallDeclined():
        declineCall();
      case NativeCallEnded():
        unawaited(leaveCall());
      case NativeCallTimedOut():
        if (_callState == LatticeCallState.ringingIncoming) {
          final info = _ringing.incomingCall;
          _ringing.stopRinging();
          _ringing.resetIncomingCall();
          if (info?.callId != null) {
            unawaited(
              _signaling.sendCallHangup(
                info!.roomId,
                info.callId!,
                reason: 'invite_timeout',
              ),
            );
          }
          _activeCallId = null;
          _activeCallRoomId = null;
          _setCallState(LatticeCallState.idle);
        } else {
          cancelOutgoingCall(isTimeout: true);
        }
    }
  }

  void _onLiveKitConnection(LiveKitConnectionEvent event) {
    switch (event) {
      case LiveKitReconnecting():
        _setCallState(LatticeCallState.reconnecting);
      case LiveKitReconnected():
        _setCallState(LatticeCallState.connected);
      case LiveKitDisconnected():
        if (_callState == LatticeCallState.disconnecting ||
            _callState == LatticeCallState.idle) {
          return;
        }
        if (_callState == LatticeCallState.joining) {
          _setCallState(LatticeCallState.idle);
          return;
        }
        final roomId = _activeCallRoomId;
        _stopMembershipWatcher();
        _activeCallRoomId = null;
        _rtcMembership.cancelMembershipRenewal();
        _callStartTime = null;
        _setCallState(LatticeCallState.failed);
        unawaited(_liveKit.cleanupLiveKit());
        if (roomId != null) {
          unawaited(
            _rtcMembership.removeMembershipEvent(roomId).catchError(
              (Object e) => debugPrint(
                '[Lattice] Error removing membership after disconnect: $e',
              ),
            ),
          );
        }
    }
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/calling/models/call_participant.dart' as ui;
import 'package:kohera/features/calling/models/call_state.dart';
import 'package:kohera/features/calling/models/incoming_call_info.dart' as model;
import 'package:kohera/features/calling/services/call_ringing_service.dart';
import 'package:kohera/features/calling/services/call_signaling_service.dart';
import 'package:kohera/features/calling/services/livekit_service.dart';
import 'package:kohera/features/calling/services/native_call_ui_service.dart';
import 'package:kohera/features/calling/services/ringtone_service.dart';
import 'package:kohera/features/calling/services/rtc_membership_service.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';

export 'package:kohera/features/calling/models/call_state.dart';
export 'package:kohera/features/calling/services/livekit_service.dart'
    show HttpPostFunction, LiveKitRoomFactory;
export 'package:kohera/features/calling/services/rtc_membership_service.dart'
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
  bool get isScreenAudioEnabled => _liveKit.isScreenAudioEnabled;
  List<livekit.Participant> get activeSpeakers => _liveKit.activeSpeakers;
  String? get cachedLivekitServiceUrl => _liveKit.cachedLivekitServiceUrl;
  bool get isCallingAvailable => _liveKit.cachedLivekitServiceUrl != null;

  List<ui.CallParticipant> get allParticipants =>
      _liveKit.allParticipants(activeCallRoomId: _activeCallRoomId);

  Future<void> toggleMicrophone() => _liveKit.toggleMicrophone();
  Future<void> toggleCamera() => _liveKit.toggleCamera();
  Future<void> toggleScreenShare({
    String? sourceId,
    bool captureScreenAudio = false,
  }) =>
      _liveKit.toggleScreenShare(
        sourceId: sourceId,
        captureScreenAudio: captureScreenAudio,
      );
  Future<void> toggleScreenAudio() => _liveKit.toggleScreenAudio();
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

  KoheraCallState _callState = KoheraCallState.idle;
  KoheraCallState get callState => _callState;

  void _setCallState(KoheraCallState next) {
    if (_callState == next) return;
    final allowed = validCallTransitions[_callState];
    if (allowed == null || !allowed.contains(next)) {
      debugPrint(
        '[Kohera] Invalid call state transition: $_callState → $next',
      );
      assert(false, 'Invalid call state transition: $_callState → $next');
      return;
    }
    _callState = next;
    notifyListeners();
    switch (next) {
      case KoheraCallState.connected:
        _nativeUi.updateNativeCallConnected();
      case KoheraCallState.idle:
      case KoheraCallState.disconnecting:
      case KoheraCallState.failed:
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

    if (_callState == KoheraCallState.ringingOutgoing && hasRemote) {
      debugPrint('[Kohera] Detected RTC membership join, treating as answer');
      unawaited(joinCall(roomId));
      return;
    }

    if (hasRemote) {
      _hadRemoteParticipant = true;
    }

    final isDm = _client.getRoomById(roomId)?.isDirectChat ?? false;
    if (isDm &&
        (_callState == KoheraCallState.connected ||
            _callState == KoheraCallState.reconnecting) &&
        !hasRemote &&
        _hadRemoteParticipant) {
      debugPrint('[Kohera] DM remote member left, ending call');
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

    debugPrint('[Kohera] CallService initialized');
  }

  void _resetState() {
    _nativeUi.endNativeCall();
    _signaling.stopSignalingListener();
    unawaited(_liveKit.cleanupLiveKit());
    _rtcMembership.cancelMembershipRenewal();
    _activeCallRoomId = null;
    _callState = KoheraCallState.idle;
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
        _callState == KoheraCallState.connected &&
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
        debugPrint('[Kohera] Error removing membership: $e');
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
    if (allowed == null || !allowed.contains(KoheraCallState.joining)) {
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
    _setCallState(KoheraCallState.joining);

    try {
      await _connectToLiveKit(roomId, room);
      _ringing.stopRinging();

      if (_callState != KoheraCallState.joining) {
        debugPrint('[Kohera] Call interrupted while joining, cleaning up');
        await _teardownCall(roomId: roomId);
        return;
      }

      _callStartTime = DateTime.now();
      _startMembershipWatcher(roomId);
      _setCallState(KoheraCallState.connected);
      debugPrint('[Kohera] Joined call in room $roomId');
    } catch (e) {
      debugPrint('[Kohera] Failed to join call: $e');
      await _teardownCall(roomId: _activeCallRoomId);
      _ringing.stopRinging();
      if (_callState == KoheraCallState.joining) {
        _setCallState(KoheraCallState.failed);
      }
    }
  }

  Future<void> leaveCall() async {
    if (_callState == KoheraCallState.ringingOutgoing) {
      cancelOutgoingCall();
      return;
    }

    if (_callState == KoheraCallState.ringingIncoming) {
      declineCall();
      return;
    }

    if (_callState == KoheraCallState.joining) {
      await _teardownCall(roomId: _activeCallRoomId);
      _activeCallId = null;
      _lastInitiatedRoomId = null;
      _setCallState(KoheraCallState.idle);
      return;
    }

    if (_activeCallRoomId == null) {
      if (_callState != KoheraCallState.idle) {
        _setCallState(KoheraCallState.idle);
      }
      return;
    }

    final roomId = _activeCallRoomId!;
    debugPrint('[Kohera] Leaving call in room $roomId');
    _stopMembershipWatcher();

    final callId = _activeCallId;
    final room = _client.getRoomById(roomId);
    if (callId != null && room != null && room.isDirectChat) {
      unawaited(_signaling.sendCallHangup(roomId, callId));
    }

    _activeCallId = null;
    _lastInitiatedRoomId = null;
    _ringing.stopRinging();
    _setCallState(KoheraCallState.disconnecting);

    await _teardownCall(roomId: roomId);
    _setCallState(KoheraCallState.idle);
  }

  // ── Ringing Actions ────────────────────────────────────────

  Future<void> acceptCall({bool withVideo = false}) async {
    if (_callState != KoheraCallState.ringingIncoming) return;
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
    if (_callState != KoheraCallState.ringingIncoming) return;
    final info = _ringing.incomingCall;

    if (info?.callId != null) {
      unawaited(_signaling.sendCallReject(info!.roomId, info.callId!));
    }

    _ringing.stopRinging();
    _ringing.resetIncomingCall();
    _setCallState(KoheraCallState.idle);
  }

  void cancelOutgoingCall({bool isTimeout = false}) {
    if (_callState != KoheraCallState.ringingOutgoing &&
        _callState != KoheraCallState.joining) {
      return;
    }

    final callId = _activeCallId;
    if (callId != null && _lastInitiatedRoomId != null) {
      final reason = isTimeout ? 'invite_timeout' : 'user_hangup';
      unawaited(
        _signaling.sendCallHangup(_lastInitiatedRoomId!, callId, reason: reason),
      );
    }

    if (_callState == KoheraCallState.joining) {
      unawaited(_teardownCall(roomId: _activeCallRoomId));
    }

    _stopMembershipWatcher();
    _ringing.stopRinging();
    _activeCallId = null;
    _lastInitiatedRoomId = null;
    _setCallState(KoheraCallState.idle);
    _activeCallRoomId = null;
  }

  Future<void> initiateCall(
    String roomId, {
    model.CallType type = model.CallType.voice,
  }) async {
    if (!_initialized) init();
    if (_callState != KoheraCallState.idle &&
        _callState != KoheraCallState.failed) {
      return;
    }

    final callId = _signaling.generateCallId();
    _activeCallId = callId;
    _lastInitiatedRoomId = roomId;
    _activeCallRoomId = roomId;
    _setCallState(KoheraCallState.ringingOutgoing);

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
    _setCallState(KoheraCallState.ringingIncoming);
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
        _setCallState(KoheraCallState.idle);
      case HangupReceived():
        _activeCallId = null;
        if (_callState == KoheraCallState.connected ||
            _callState == KoheraCallState.reconnecting) {
          unawaited(leaveCall());
        } else {
          _handleCallEnded();
        }
      case GlareResolved():
        _activeCallId = null;
        _activeCallRoomId = null;
        _lastInitiatedRoomId = null;
        _ringing.stopRinging();
        _setCallState(KoheraCallState.idle);
        _handleSignalingIncomingInvite(event.incomingInvite);
    }
  }

  void _handleSignalingIncomingInvite(IncomingInvite event) {
    if (_callState != KoheraCallState.idle &&
        _callState != KoheraCallState.failed) {
      debugPrint('[Kohera] Ignoring duplicate invite, already in $_callState');
      return;
    }
    _activeCallId = event.callId;
    _ringing.pushIncomingCall(event.info);
    _setCallState(KoheraCallState.ringingIncoming);
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
    if (_callState != KoheraCallState.idle &&
        _callState != KoheraCallState.disconnecting) {
      _setCallState(KoheraCallState.idle);
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
        if (_callState == KoheraCallState.ringingIncoming) {
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
          _setCallState(KoheraCallState.idle);
        } else {
          cancelOutgoingCall(isTimeout: true);
        }
    }
  }

  void _onLiveKitConnection(LiveKitConnectionEvent event) {
    switch (event) {
      case LiveKitReconnecting():
        _setCallState(KoheraCallState.reconnecting);
      case LiveKitReconnected():
        _setCallState(KoheraCallState.connected);
      case LiveKitDisconnected():
        if (_callState == KoheraCallState.disconnecting ||
            _callState == KoheraCallState.idle) {
          return;
        }
        if (_callState == KoheraCallState.joining) {
          _setCallState(KoheraCallState.idle);
          return;
        }
        final roomId = _activeCallRoomId;
        _stopMembershipWatcher();
        _activeCallRoomId = null;
        _rtcMembership.cancelMembershipRenewal();
        _callStartTime = null;
        _setCallState(KoheraCallState.failed);
        unawaited(_liveKit.cleanupLiveKit());
        if (roomId != null) {
          unawaited(
            _rtcMembership.removeMembershipEvent(roomId).catchError(
              (Object e) => debugPrint(
                '[Kohera] Error removing membership after disconnect: $e',
              ),
            ),
          );
        }
    }
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
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
    show
        HttpPostFunction,
        JoinPhase,
        LiveKitParticipantEvent,
        LiveKitParticipantJoined,
        LiveKitParticipantLeft,
        LiveKitRoomFactory;
export 'package:kohera/features/calling/services/rtc_membership_service.dart'
    show callMemberEventType, membershipExpiresMs, membershipRenewalInterval;

// ── Call Service ────────────────────────────────────────────

class CallService extends ChangeNotifier with WidgetsBindingObserver {
  CallService({
    required Client client,
    RingtoneService? ringtoneService,
    NativeCallUiService? nativeCallUiService,
  }) : _client = client {
    _rtcMembership = RtcMembershipService(client: client);
    _liveKit = LiveKitService(
      client: client,
      onChanged: notifyListeners,
    );
    _signaling = CallSignalingService(client: client);
    _ringing = CallRingingService(ringtoneService: ringtoneService);
    _nativeUi = nativeCallUiService ?? NativeCallUiService();
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
  StreamSubscription<LiveKitParticipantEvent>? _liveKitParticipantSub;
  StreamSubscription<({String roomId, StrippedStateEvent state})>?
      _membershipWatcherSub;
  StreamSubscription<({String roomId, StrippedStateEvent state})>?
      _incomingRingSub;

  String? _incomingCallerStateKey;

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
  JoinPhase? get joinPhase => _liveKit.joinPhase;

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
    final prev = _callState;
    _callState = next;
    notifyListeners();
    _playStateTransitionSound(prev, next);
    switch (next) {
      case KoheraCallState.connected:
        if (_currentCallFromPushKit) {
          _nativeUi.dismissCallKitSilently();
        } else {
          _nativeUi.updateNativeCallConnected();
        }
      case KoheraCallState.idle:
      case KoheraCallState.disconnecting:
      case KoheraCallState.failed:
        _nativeUi.resetEndingGuard();
        _nativeUi.endNativeCall();
      default:
        break;
    }
  }

  void _playStateTransitionSound(KoheraCallState prev, KoheraCallState next) {
    final wasInCall = prev == KoheraCallState.connected ||
        prev == KoheraCallState.reconnecting;
    if (next == KoheraCallState.connected &&
        prev != KoheraCallState.reconnecting) {
      _ringing.playUserJoined();
    } else if (wasInCall &&
        (next == KoheraCallState.idle ||
            next == KoheraCallState.disconnecting ||
            next == KoheraCallState.failed)) {
      _ringing.playUserLeft();
    }
  }

  bool _voipPushHandlesCallKit = false;
  void setVoipPushHandlesCallKit(bool value) =>
      _voipPushHandlesCallKit = value;

  bool _currentCallFromPushKit = false;

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
  Future<void>? _pendingMembershipSend;

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

  // ── Incoming Ring (m.call.member) ───────────────────────────

  void _onGlobalRoomState(
      ({String roomId, StrippedStateEvent state}) update,) {
    if (update.state.type != callMemberEventType) return;

    final stateKey = update.state.stateKey;
    if (stateKey == null) return;

    final localPrefix = '_${_client.userID ?? ''}_';
    if (stateKey.startsWith(localPrefix)) return;

    final room = _client.getRoomById(update.roomId);
    if (room == null || !room.isDirectChat) return;

    final content = update.state.content;
    final isActive = content.isNotEmpty;

    if (isActive) {
      _handleRemoteMembershipJoined(
        roomId: update.roomId,
        stateKey: stateKey,
        content: content,
        room: room,
      );
    } else {
      _handleRemoteMembershipRemoved(roomId: update.roomId, stateKey: stateKey);
    }
  }

  void _handleRemoteMembershipJoined({
    required String roomId,
    required String stateKey,
    required Map<String, Object?> content,
    required Room room,
  }) {
    if (_callState != KoheraCallState.idle &&
        _callState != KoheraCallState.failed) {
      return;
    }

    final isVideo = content[kIoKoheraIsVideo] == true;

    final senderId =
        RtcMembershipService.userIdFromStateKey(stateKey) ?? stateKey;
    final sender = room.unsafeGetUserFromMemoryOrFallback(senderId);
    final callerName = sender.calcDisplayname();
    final callerAvatarUrl = sender.avatarUrl;

    final info = model.IncomingCallInfo(
      roomId: roomId,
      callId: '',
      callerName: callerName,
      callerAvatarUrl: callerAvatarUrl,
      isVideo: isVideo,
    );

    _incomingCallerStateKey = stateKey;
    _activeCallId = '';
    _currentCallFromPushKit = _voipPushHandlesCallKit;
    _ringing.pushIncomingCall(info);
    _setCallState(KoheraCallState.ringingIncoming);

    if (!_voipPushHandlesCallKit) {
      _nativeUi.showNativeIncomingCall(
        callId: '',
        roomId: roomId,
        callerName: callerName,
        callerAvatarUrl: callerAvatarUrl,
        isVideo: isVideo,
      );
    }
    if (kIsWeb || isNativeDesktop) {
      _ringing.playRingtone();
    }
    debugPrint(
      '[Kohera] Incoming m.call.member from $senderId in $roomId '
      '(video=$isVideo)',
    );
  }

  void _handleRemoteMembershipRemoved({
    required String roomId,
    required String stateKey,
  }) {
    if (_callState != KoheraCallState.ringingIncoming) return;

    if (_incomingCallerStateKey != null) {
      if (_incomingCallerStateKey != stateKey) return;
    } else {
      if (RtcMembershipService.roomHasRemoteActiveCall(_client, roomId)) {
        return;
      }
    }

    debugPrint('[Kohera] Caller cancelled before answer; tearing down ring');
    _incomingCallerStateKey = null;
    _ringing.stopRinging();
    _ringing.resetIncomingCall();
    _activeCallId = null;
    _nativeUi.endNativeCall();
    _setCallState(KoheraCallState.idle);
  }

  // ── Lifecycle ──────────────────────────────────────────────

  void init() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_liveKit.fetchWellKnownLiveKit());
    _signaling.startSignalingListener();
    _nativeUi.init(getCallState: () => _callState.name);

    _signalingEventSub = _signaling.events.listen(_onSignalingEvent);
    _nativeActionSub = _nativeUi.actions.listen(_onNativeAction);
    _liveKitConnectionSub = _liveKit.connectionEvents.listen(_onLiveKitConnection);
    _liveKitParticipantSub =
        _liveKit.participantEvents.listen(_onLiveKitParticipant);
    _incomingRingSub = _client.onRoomState.stream.listen(_onGlobalRoomState);

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
    _currentCallFromPushKit = false;
    _callStartTime = null;
    _hadRemoteParticipant = false;
    unawaited(_signalingEventSub?.cancel());
    _signalingEventSub = null;
    unawaited(_nativeActionSub?.cancel());
    _nativeActionSub = null;
    unawaited(_liveKitConnectionSub?.cancel());
    _liveKitConnectionSub = null;
    unawaited(_liveKitParticipantSub?.cancel());
    _liveKitParticipantSub = null;
    unawaited(_incomingRingSub?.cancel());
    _incomingRingSub = null;
    _incomingCallerStateKey = null;
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
    final pending = _pendingMembershipSend;
    _pendingMembershipSend = null;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
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

    _rtcMembership.startMembershipRenewal(
      roomId,
      livekitAlias,
      livekitServiceUrl: livekitServiceUrl,
    );

    final membershipFuture = _rtcMembership
        .sendMembershipEvent(
      roomId,
      livekitAlias,
      livekitServiceUrl: livekitServiceUrl,
    )
        .catchError((Object e) {
      debugPrint('[Kohera] Initial membership send failed: $e');
    });
    _pendingMembershipSend = membershipFuture;

    await Future.wait([
      membershipFuture.whenComplete(() {
        if (identical(_pendingMembershipSend, membershipFuture)) {
          _pendingMembershipSend = null;
        }
      }),
      _liveKit.connectLiveKit(
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
      ),
    ]);
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
    _incomingCallerStateKey = null;

    await joinCall(info.roomId);
  }

  void declineCall() {
    if (_callState != KoheraCallState.ringingIncoming) return;

    _ringing.stopRinging();
    _ringing.resetIncomingCall();
    _incomingCallerStateKey = null;
    _setCallState(KoheraCallState.idle);
  }

  void cancelOutgoingCall({bool isTimeout = false}) {
    if (_callState != KoheraCallState.ringingOutgoing &&
        _callState != KoheraCallState.joining) {
      return;
    }

    final roomId = _lastInitiatedRoomId;
    if (roomId != null) {
      unawaited(
        _rtcMembership.removeMembershipEvent(roomId).catchError(
          (Object e) => debugPrint(
            '[Kohera] Failed to remove ring-phase membership: $e',
          ),
        ),
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

    final room = _client.getRoomById(roomId);
    if (room == null) return;

    _activeCallId = '';
    _lastInitiatedRoomId = roomId;
    _activeCallRoomId = roomId;
    _setCallState(KoheraCallState.ringingOutgoing);

    final callerName = room.getLocalizedDisplayname();
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

    if (_liveKit.cachedLivekitServiceUrl == null) {
      await _liveKit.fetchWellKnownLiveKit();
    }
    final livekitServiceUrl = _liveKit.cachedLivekitServiceUrl;
    if (livekitServiceUrl == null) {
      debugPrint('[Kohera] initiateCall aborted: LiveKit service URL missing');
      cancelOutgoingCall();
      return;
    }
    final livekitAlias =
        room.canonicalAlias.isNotEmpty ? room.canonicalAlias : room.id;

    try {
      await _rtcMembership.sendMembershipEvent(
        roomId,
        livekitAlias,
        livekitServiceUrl: livekitServiceUrl,
        isVideo: isVideo,
        expiresMs: ringPhaseExpiresMs,
      );
      debugPrint('[Kohera] Ring-phase m.call.member sent for $roomId');
      if (_callState != KoheraCallState.ringingOutgoing) {
        debugPrint(
          '[Kohera] Outgoing call was cancelled mid-send; removing stale '
          'membership',
        );
        unawaited(
          _rtcMembership.removeMembershipEvent(roomId).catchError(
            (Object e) => debugPrint(
              '[Kohera] Failed to remove stale ring-phase membership: $e',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to send ring-phase membership: $e');
      cancelOutgoingCall();
    }
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
    bool callKitAlreadyShown = false,
  }) {
    if (!_initialized) init();
    if (_callState != KoheraCallState.idle &&
        _callState != KoheraCallState.failed) {
      debugPrint(
        '[Kohera] Ignoring duplicate push invite, already in $_callState',
      );
      return;
    }
    _activeCallId = callId;
    _currentCallFromPushKit = callKitAlreadyShown;
    final info = model.IncomingCallInfo(
      roomId: roomId,
      callId: callId,
      callerName: callerName,
      isVideo: isVideo,
    );
    _ringing.pushIncomingCall(info);
    _setCallState(KoheraCallState.ringingIncoming);
    if (!callKitAlreadyShown) {
      _nativeUi.showNativeIncomingCall(
        callId: callId,
        roomId: roomId,
        callerName: callerName,
        callerAvatarUrl: null,
        isVideo: isVideo,
      );
    }
    if (kIsWeb || isNativeDesktop) {
      _ringing.playRingtone();
    }
  }

  void attachPrePresentedCallKit({required String nativeCallId}) {
    if (!_initialized) init();
    _nativeUi.attachExistingNativeCall(nativeCallId);
  }

  void endCallFromPushKit() {
    if (_callState != KoheraCallState.ringingIncoming) return;
    _ringing.stopRinging();
    _ringing.resetIncomingCall();
    _activeCallId = null;
    _setCallState(KoheraCallState.idle);
  }

  // ── Event Handlers ─────────────────────────────────────────

  void _onSignalingEvent(SignalingEvent event) {
    switch (event) {
      case LegacyCallAttempt():
        debugPrint(
          '[Kohera] Legacy call attempt in ${event.roomId} from '
          '${event.senderId} — surfaced as missed-call marker, no ring',
        );
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
          _ringing.stopRinging();
          _ringing.resetIncomingCall();
          _incomingCallerStateKey = null;
          _activeCallId = null;
          _activeCallRoomId = null;
          _setCallState(KoheraCallState.idle);
        } else {
          cancelOutgoingCall(isTimeout: true);
        }
    }
  }

  void _onLiveKitParticipant(LiveKitParticipantEvent event) {
    if (_callState != KoheraCallState.connected) return;
    switch (event) {
      case LiveKitParticipantJoined():
        _ringing.playUserJoined();
      case LiveKitParticipantLeft():
        _ringing.playUserLeft();
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

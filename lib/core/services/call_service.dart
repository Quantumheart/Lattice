import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:http/http.dart' as http;
import 'package:lattice/features/calling/models/incoming_call_info.dart' as model;
import 'package:lattice/features/calling/services/ringtone_service.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as webrtc;

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

// ── WebRTC Delegate ─────────────────────────────────────────

class _LatticeWebRTCDelegate implements WebRTCDelegate {
  _LatticeWebRTCDelegate(this._callService);

  final CallService _callService;

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
  Future<void> playRingtone() async {
    await _callService._ringtoneService?.playRingtone();
  }

  @override
  Future<void> stopRingtone() async {
    await _callService._ringtoneService?.stop();
  }

  @override
  Future<void> registerListeners(CallSession session) async {}

  @override
  Future<void> handleNewCall(CallSession session) async {
    _inCall = true;
    _callService._handleIncomingCall(session);
  }

  @override
  Future<void> handleCallEnded(CallSession session) async {
    _inCall = false;
    _callService._handleCallEnded();
  }

  @override
  Future<void> handleMissedCall(CallSession session) async {
    _callService._handleCallEnded();
  }

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {
    _inCall = true;
    _callService._handleIncomingGroupCall(groupCall);
  }

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {
    _inCall = false;
    _callService._handleCallEnded();
  }

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get canHandleNewCall => !_inCall;

  @override
  EncryptionKeyProvider? get keyProvider => null;
}

// ── Call Service ────────────────────────────────────────────

class CallService extends ChangeNotifier {
  CallService({required Client client}) : _client = client;

  Client _client;
  Client get client => _client;

  bool _disposed = false;

  // ── VoIP ────────────────────────────────────────────────

  VoIP? _voip;
  VoIP? get voip => _voip;

  @visibleForTesting
  set voipForTest(VoIP? value) => _voip = value;

  _LatticeWebRTCDelegate? _webrtcDelegate;

  void initVoip() {
    _webrtcDelegate = _LatticeWebRTCDelegate(this);
    _voip = VoIP(_client, _webrtcDelegate!);
    debugPrint('[Lattice] VoIP initialized');
  }

  // ── Ringtone ───────────────────────────────────────────

  RingtoneService? _ringtoneService;

  set ringtoneService(RingtoneService? service) => _ringtoneService = service;

  // ── State ───────────────────────────────────────────────

  LatticeCallState _callState = LatticeCallState.idle;
  LatticeCallState get callState => _callState;

  bool _joining = false;

  GroupCallSession? _activeGroupCall;
  GroupCallSession? get activeGroupCall => _activeGroupCall;

  String? get activeCallRoomId => _activeGroupCall?.room.id;

  StreamSubscription<MatrixRTCCallEvent>? _callEventSub;

  // ── Ringing State ─────────────────────────────────────────

  model.IncomingCallInfo? _incomingCall;
  model.IncomingCallInfo? get incomingCall => _incomingCall;

  Timer? _ringingTimer;
  DateTime? _callStartTime;

  final StreamController<model.IncomingCallInfo> _incomingCallController =
      StreamController<model.IncomingCallInfo>.broadcast();
  Stream<model.IncomingCallInfo> get incomingCallStream =>
      _incomingCallController.stream;

  Duration? get callElapsed =>
      _callStartTime != null ? DateTime.now().difference(_callStartTime!) : null;

  // ── LiveKit State ───────────────────────────────────────

  livekit.Room? _livekitRoom;
  livekit.Room? get livekitRoom => _livekitRoom;

  livekit.EventsListener<livekit.RoomEvent>? _livekitListener;

  List<livekit.RemoteParticipant> _participants = [];
  List<livekit.RemoteParticipant> get participants =>
      List.unmodifiable(_participants);

  bool _isMicEnabled = false;
  bool get isMicEnabled => _isMicEnabled;

  bool _isCameraEnabled = false;
  bool get isCameraEnabled => _isCameraEnabled;

  bool _isScreenShareEnabled = false;
  bool get isScreenShareEnabled => _isScreenShareEnabled;

  List<livekit.Participant> _activeSpeakers = [];
  List<livekit.Participant> get activeSpeakers =>
      List.unmodifiable(_activeSpeakers);

  LiveKitRoomFactory _roomFactory = livekit.Room.new;

  @visibleForTesting
  set roomFactoryForTest(LiveKitRoomFactory factory) => _roomFactory = factory;

  HttpPostFunction _httpPost = http.post;

  @visibleForTesting
  set httpPostForTest(HttpPostFunction fn) => _httpPost = fn;

  // ── Queries ─────────────────────────────────────────────

  bool roomHasActiveCall(String roomId) {
    if (_voip == null) return false;
    final room = _client.getRoomById(roomId);
    if (room == null) return false;
    return room.hasActiveGroupCall(_voip!);
  }

  List<String> activeCallIdsForRoom(String roomId) {
    if (_voip == null) return const [];
    final room = _client.getRoomById(roomId);
    if (room == null) return const [];
    return room.activeGroupCallIds(_voip!);
  }

  int callParticipantCount(String roomId, String groupCallId) {
    if (_voip == null) return 0;
    final room = _client.getRoomById(roomId);
    if (room == null) return 0;
    return room.groupCallParticipantCount(groupCallId, _voip!);
  }

  List<CallMembership> callMembershipsForRoom(String roomId) {
    if (_voip == null) return const [];
    final room = _client.getRoomById(roomId);
    if (room == null) return const [];
    final memberships = room.getCallMembershipsFromRoom(_voip!);
    return memberships.values.expand((list) => list).toList();
  }

  // ── Incoming Call Handling ─────────────────────────────────

  void _handleIncomingCall(CallSession session) {
    if (_callState != LatticeCallState.idle) return;

    final room = session.room;
    final caller = room.unsafeGetUserFromMemoryOrFallback(session.remoteUserId ?? '');

    _incomingCall = model.IncomingCallInfo(
      roomId: room.id,
      callerName: caller.calcDisplayname(),
      callerAvatarUrl: caller.avatarUrl,
      isVideo: session.type == CallType.kVideo,
    );
    _callState = LatticeCallState.ringingIncoming;
    _incomingCallController.add(_incomingCall!);
    notifyListeners();
  }

  void _handleIncomingGroupCall(GroupCallSession groupCall) {
    if (_callState != LatticeCallState.idle) return;

    final room = groupCall.room;
    _incomingCall = model.IncomingCallInfo(
      roomId: room.id,
      callerName: room.getLocalizedDisplayname(),
      isGroupCall: true,
    );
    _callState = LatticeCallState.ringingIncoming;
    _incomingCallController.add(_incomingCall!);
    notifyListeners();
  }

  void _handleCallEnded() {
    if (_callState == LatticeCallState.ringingIncoming ||
        _callState == LatticeCallState.ringingOutgoing) {
      _incomingCall = null;
      _ringingTimer?.cancel();
      _ringingTimer = null;
      _callState = LatticeCallState.idle;
      unawaited(_ringtoneService?.stop());
      notifyListeners();
    }
  }

  // ── Ringing Actions ────────────────────────────────────────

  void acceptCall({bool withVideo = false}) {
    if (_callState != LatticeCallState.ringingIncoming) return;
    final info = _incomingCall;
    if (info == null) return;

    _incomingCall = null;
    _callState = LatticeCallState.joining;
    unawaited(_ringtoneService?.stop());
    notifyListeners();

    unawaited(joinCall(info.roomId));
  }

  void declineCall() {
    if (_callState != LatticeCallState.ringingIncoming) return;
    _incomingCall = null;
    _callState = LatticeCallState.idle;
    unawaited(_ringtoneService?.stop());
    notifyListeners();
  }

  void cancelOutgoingCall() {
    if (_callState != LatticeCallState.ringingOutgoing) return;
    _ringingTimer?.cancel();
    _ringingTimer = null;
    _callState = LatticeCallState.idle;
    unawaited(_ringtoneService?.stop());
    notifyListeners();
    unawaited(leaveCall());
  }

  Future<void> initiateCall(String roomId, {model.CallType type = model.CallType.voice}) async {
    if (_voip == null) initVoip();
    if (_callState != LatticeCallState.idle) return;

    _callState = LatticeCallState.ringingOutgoing;
    notifyListeners();

    unawaited(_ringtoneService?.playDialtone());

    _ringingTimer = Timer(const Duration(seconds: 60), () {
      if (_callState == LatticeCallState.ringingOutgoing) {
        cancelOutgoingCall();
      }
    });

    await joinCall(roomId);
  }

  // ── Actions ─────────────────────────────────────────────

  Future<void> joinCall(
    String roomId, {
    CallBackend? backend,
    String? groupCallId,
  }) async {
    if (_voip == null) return;
    if (_callState != LatticeCallState.idle &&
        _callState != LatticeCallState.joining &&
        _callState != LatticeCallState.ringingOutgoing) {
      if (_joining) return;
      debugPrint('[Lattice] Cannot join call: already in state $_callState');
      return;
    }

    final room = _client.getRoomById(roomId);
    if (room == null) {
      debugPrint('[Lattice] Cannot join call: room $roomId not found');
      return;
    }

    _joining = true;
    if (_callState != LatticeCallState.ringingOutgoing) {
      _callState = LatticeCallState.joining;
    }
    notifyListeners();

    try {
      final resolvedCallId = groupCallId ?? _resolveGroupCallId(room);
      final resolvedBackend = backend ?? _resolveBackend(room, resolvedCallId);

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

      if (resolvedBackend is LiveKitBackend) {
        await _connectLiveKit(resolvedBackend);
      }

      _ringingTimer?.cancel();
      _ringingTimer = null;

      _callStartTime = DateTime.now();
      _callState = LatticeCallState.connected;
      unawaited(_ringtoneService?.stop());
      notifyListeners();
      debugPrint(
        '[Lattice] Joined call ${groupCall.groupCallId} in room $roomId',
      );
    } catch (e) {
      debugPrint('[Lattice] Failed to join call: $e');
      await _cleanupLiveKit();
      _callState = LatticeCallState.failed;
      _activeGroupCall = null;
      _ringingTimer?.cancel();
      _ringingTimer = null;

      unawaited(_callEventSub?.cancel());
      _callEventSub = null;
      unawaited(_ringtoneService?.stop());
      notifyListeners();
    } finally {
      _joining = false;
    }
  }

  Future<void> leaveCall() async {
    if (_activeGroupCall == null) return;

    final callId = _activeGroupCall!.groupCallId;
    debugPrint('[Lattice] Leaving call $callId');

    _callState = LatticeCallState.disconnecting;
    notifyListeners();

    await _cleanupLiveKit();

    try {
      await _activeGroupCall!.leave();
    } catch (e) {
      debugPrint('[Lattice] Error leaving call: $e');
    }

    unawaited(_callEventSub?.cancel());
    _callEventSub = null;
    _activeGroupCall = null;
    _callStartTime = null;
    _callState = LatticeCallState.idle;
    notifyListeners();
  }

  // ── Track Toggles ─────────────────────────────────────────

  Future<void> toggleMicrophone() async {
    final localParticipant = _livekitRoom?.localParticipant;
    if (localParticipant == null) return;

    _isMicEnabled = !_isMicEnabled;
    notifyListeners();

    try {
      await localParticipant.setMicrophoneEnabled(_isMicEnabled);
    } catch (e) {
      debugPrint('[Lattice] Failed to toggle microphone: $e');
      _isMicEnabled = !_isMicEnabled;
      notifyListeners();
    }
  }

  Future<void> toggleCamera() async {
    final localParticipant = _livekitRoom?.localParticipant;
    if (localParticipant == null) return;

    _isCameraEnabled = !_isCameraEnabled;
    notifyListeners();

    try {
      await localParticipant.setCameraEnabled(_isCameraEnabled);
    } catch (e) {
      debugPrint('[Lattice] Failed to toggle camera: $e');
      _isCameraEnabled = !_isCameraEnabled;
      notifyListeners();
    }
  }

  Future<void> toggleScreenShare() async {
    final localParticipant = _livekitRoom?.localParticipant;
    if (localParticipant == null) return;

    _isScreenShareEnabled = !_isScreenShareEnabled;
    notifyListeners();

    try {
      await localParticipant.setScreenShareEnabled(_isScreenShareEnabled);
    } catch (e) {
      debugPrint('[Lattice] Failed to toggle screen share: $e');
      _isScreenShareEnabled = !_isScreenShareEnabled;
      notifyListeners();
    }
  }

  // ── TURN Server ─────────────────────────────────────────

  Future<TurnServerCredentials?> fetchTurnServers() async {
    try {
      return await _client.getTurnServer();
    } catch (e) {
      debugPrint('[Lattice] Failed to fetch TURN servers: $e');
      return null;
    }
  }

  // ── Lifecycle ───────────────────────────────────────────

  void _resetState() {
    unawaited(_cleanupLiveKit());
    _activeGroupCall = null;
    _callState = LatticeCallState.idle;
    _voip = null;
    _webrtcDelegate = null;
    _incomingCall = null;
    _ringingTimer?.cancel();
    _ringingTimer = null;
    _callStartTime = null;
    unawaited(_ringtoneService?.stop());
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
    unawaited(_incomingCallController.close());
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ── LiveKit Private ─────────────────────────────────────

  Future<({String url, String token})> _fetchLiveKitToken(
    LiveKitBackend backend,
  ) async {
    final openId = await _client.requestOpenIdToken(
      _client.userID!,
      {},
    );

    final response = await _httpPost(
      Uri.parse(backend.livekitServiceUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'access_token': openId.accessToken,
        'token_type': openId.tokenType,
        'matrix_server_name': openId.matrixServerName,
        'expires_in': openId.expiresIn,
        'room_alias': backend.livekitAlias,
        'device_id': _client.deviceID,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'LiveKit token exchange failed: ${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (url: json['url'] as String, token: json['token'] as String);
  }

  Future<void> _connectLiveKit(LiveKitBackend backend) async {
    final credentials = await _fetchLiveKitToken(backend);

    _livekitRoom = _roomFactory();
    _livekitListener = _livekitRoom!.createListener();
    _subscribeLiveKitEvents();

    await _livekitRoom!.connect(credentials.url, credentials.token);

    _isMicEnabled = false;
    _isCameraEnabled = false;
    _isScreenShareEnabled = false;
    _syncParticipants();
  }

  void _subscribeLiveKitEvents() {
    final listener = _livekitListener!;

    listener.on<livekit.RoomReconnectingEvent>((_) {
      _callState = LatticeCallState.reconnecting;
      notifyListeners();
    });

    listener.on<livekit.RoomReconnectedEvent>((_) {
      _callState = LatticeCallState.connected;
      notifyListeners();
    });

    listener.on<livekit.RoomDisconnectedEvent>((_) {
      unawaited(_cleanupLiveKit());
      final groupCall = _activeGroupCall;
      _activeGroupCall = null;
      unawaited(_callEventSub?.cancel());
      _callEventSub = null;
      _callStartTime = null;
      _callState = LatticeCallState.failed;
      notifyListeners();
      if (groupCall != null) {
        unawaited(
          groupCall.leave().catchError(
            (Object e) => debugPrint('[Lattice] Error leaving group call after disconnect: $e'),
          ),
        );
      }
    });

    listener.on<livekit.ParticipantConnectedEvent>((_) {
      _syncParticipants();
      notifyListeners();
    });

    listener.on<livekit.ParticipantDisconnectedEvent>((_) {
      _syncParticipants();
      notifyListeners();
    });

    listener.on<livekit.ActiveSpeakersChangedEvent>((event) {
      _activeSpeakers = event.speakers.toList();
      notifyListeners();
    });

    listener.on<livekit.TrackMutedEvent>((_) => notifyListeners());
    listener.on<livekit.TrackUnmutedEvent>((_) => notifyListeners());
    listener.on<livekit.TrackSubscribedEvent>((_) => notifyListeners());
    listener.on<livekit.TrackUnsubscribedEvent>((_) => notifyListeners());
  }

  void _syncParticipants() {
    _participants =
        _livekitRoom?.remoteParticipants.values.toList() ?? [];
  }

  Future<void> _cleanupLiveKit() async {
    final listener = _livekitListener;
    final room = _livekitRoom;
    _livekitListener = null;
    _livekitRoom = null;
    _participants = [];
    _activeSpeakers = [];
    _isMicEnabled = false;
    _isCameraEnabled = false;
    _isScreenShareEnabled = false;

    try {
      await room?.disconnect();
    } catch (e) {
      debugPrint('[Lattice] Error disconnecting LiveKit: $e');
    }
    try {
      await listener?.dispose();
    } catch (_) {}
    try {
      await room?.dispose();
    } catch (_) {}
  }

  // ── Private ─────────────────────────────────────────────

  GroupCallSession? _findGroupCall(Room room, String callId) {
    for (final groupCall in _voip!.groupCalls.values) {
      if (groupCall.room.id == room.id && groupCall.groupCallId == callId) {
        return groupCall;
      }
    }
    return null;
  }

  GroupCallSession _findOrCreateGroupCall(
    Room room,
    CallBackend backend,
    String? callId,
  ) {
    if (callId != null) {
      final existing = _findGroupCall(room, callId);
      if (existing != null) return existing;
    }

    return GroupCallSession.withAutoGenId(
      room,
      _voip!,
      backend,
      'm.call',
      'm.room',
      callId,
    );
  }

  CallBackend _resolveBackend(Room room, String? callId) {
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
    debugPrint(
      '[Lattice] No active membership found for call $callId, falling back to MeshBackend',
    );
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
          unawaited(_cleanupLiveKit());
          _callState = LatticeCallState.idle;
          _activeGroupCall = null;
          _callStartTime = null;
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

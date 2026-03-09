import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as webrtc;

// ── Call State ──────────────────────────────────────────────

enum LatticeCallState {
  idle,
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
  _LatticeWebRTCDelegate(this._onCallStateChanged);

  final VoidCallback _onCallStateChanged;

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
  Future<void> playRingtone() async {}

  @override
  Future<void> stopRingtone() async {}

  @override
  Future<void> registerListeners(CallSession session) async {}

  @override
  Future<void> handleNewCall(CallSession session) async {
    _inCall = true;
    _onCallStateChanged();
  }

  @override
  Future<void> handleCallEnded(CallSession session) async {
    _inCall = false;
    _onCallStateChanged();
  }

  @override
  Future<void> handleMissedCall(CallSession session) async {}

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {
    _inCall = true;
    _onCallStateChanged();
  }

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {
    _inCall = false;
    _onCallStateChanged();
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
    _webrtcDelegate = _LatticeWebRTCDelegate(notifyListeners);
    _voip = VoIP(_client, _webrtcDelegate!);
    debugPrint('[Lattice] VoIP initialized');
  }

  void _resetState() {
    _cleanupLiveKit();
    _activeGroupCall = null;
    _callState = LatticeCallState.idle;
    _voip = null;
    _webrtcDelegate = null;
  }

  void updateClient(Client newClient) {
    if (identical(_client, newClient)) return;
    _resetState();
    _client = newClient;
  }

  // ── State ───────────────────────────────────────────────

  LatticeCallState _callState = LatticeCallState.idle;
  LatticeCallState get callState => _callState;

  GroupCallSession? _activeGroupCall;
  GroupCallSession? get activeGroupCall => _activeGroupCall;

  String? get activeCallRoomId => _activeGroupCall?.room.id;

  StreamSubscription<MatrixRTCCallEvent>? _callEventSub;

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

  // ── Actions ─────────────────────────────────────────────

  Future<void> joinCall(
    String roomId, {
    CallBackend? backend,
    String? groupCallId,
  }) async {
    if (_voip == null) return;
    if (_callState != LatticeCallState.idle) {
      debugPrint('[Lattice] Cannot join call: already in state $_callState');
      return;
    }

    final room = _client.getRoomById(roomId);
    if (room == null) {
      debugPrint('[Lattice] Cannot join call: room $roomId not found');
      return;
    }

    _callState = LatticeCallState.joining;
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

      _callState = LatticeCallState.connected;
      notifyListeners();
      debugPrint(
        '[Lattice] Joined call ${groupCall.groupCallId} in room $roomId',
      );
    } catch (e) {
      debugPrint('[Lattice] Failed to join call: $e');
      _cleanupLiveKit();
      _callState = LatticeCallState.failed;
      _activeGroupCall = null;
      unawaited(_callEventSub?.cancel());
      _callEventSub = null;
      notifyListeners();
    }
  }

  Future<void> leaveCall() async {
    if (_activeGroupCall == null) return;

    final callId = _activeGroupCall!.groupCallId;
    debugPrint('[Lattice] Leaving call $callId');

    _callState = LatticeCallState.disconnecting;
    notifyListeners();

    await _disconnectLiveKit();

    try {
      await _activeGroupCall!.leave();
    } catch (e) {
      debugPrint('[Lattice] Error leaving call: $e');
    }

    unawaited(_callEventSub?.cancel());
    _callEventSub = null;
    _activeGroupCall = null;
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

  @override
  void dispose() {
    _disposed = true;
    _resetState();
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
      _cleanupLiveKit();
      _callState = LatticeCallState.failed;
      notifyListeners();
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

  Future<void> _disconnectLiveKit() async {
    try {
      await _livekitRoom?.disconnect();
    } catch (e) {
      debugPrint('[Lattice] Error disconnecting LiveKit: $e');
    }
    _cleanupLiveKit();
  }

  void _cleanupLiveKit() {
    final listener = _livekitListener;
    final room = _livekitRoom;
    _livekitListener = null;
    _livekitRoom = null;
    if (listener != null) unawaited(listener.dispose());
    if (room != null) unawaited(room.dispose());
    _participants = [];
    _activeSpeakers = [];
    _isMicEnabled = false;
    _isCameraEnabled = false;
    _isScreenShareEnabled = false;
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
          _callState = LatticeCallState.idle;
          _activeGroupCall = null;
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

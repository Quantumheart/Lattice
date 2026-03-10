import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/features/calling/models/call_participant.dart' as ui;
import 'package:lattice/features/calling/models/incoming_call_info.dart' as model;
import 'package:lattice/features/calling/services/ringtone_service.dart';
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

const _callMemberEventType = 'org.matrix.msc3401.call.member';
const _membershipExpiresMs = 14400000;
const _membershipRenewalInterval = Duration(minutes: 5);

// ── Call Service ────────────────────────────────────────────

class CallService extends ChangeNotifier {
  CallService({required Client client}) : _client = client;

  Client _client;
  Client get client => _client;

  bool _disposed = false;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;
    unawaited(fetchWellKnownLiveKit());
    debugPrint('[Lattice] CallService initialized');
  }

  // ── Ringtone ───────────────────────────────────────────

  RingtoneService? _ringtoneService;

  set ringtoneService(RingtoneService? service) => _ringtoneService = service;

  void _stopRinging() {
    _ringingTimer?.cancel();
    _ringingTimer = null;
    unawaited(_ringtoneService?.stop());
  }

  // ── State ───────────────────────────────────────────────

  LatticeCallState _callState = LatticeCallState.idle;
  LatticeCallState get callState => _callState;

  bool _joining = false;
  bool _endedDuringJoin = false;

  @visibleForTesting
  bool get isJoining => _joining;

  String? _activeCallRoomId;
  String? get activeCallRoomId => _activeCallRoomId;

  Timer? _membershipRenewalTimer;

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
  HttpPostFunction get httpPostForTest => _httpPost;

  @visibleForTesting
  set httpPostForTest(HttpPostFunction fn) => _httpPost = fn;

  // ── Participant Aggregation ─────────────────────────────

  List<ui.CallParticipant> get allParticipants => _buildParticipantList();

  List<ui.CallParticipant> _buildParticipantList() {
    final result = <ui.CallParticipant>[];
    if (_livekitRoom == null) return result;

    final local = _livekitRoom!.localParticipant;
    if (local != null) {
      result.add(ui.CallParticipant.fromLiveKit(
        local,
        activeSpeakers: _activeSpeakers,
        isLocal: true,
      ),);
    }
    for (final p in _participants) {
      result.add(ui.CallParticipant.fromLiveKit(p, activeSpeakers: _activeSpeakers),);
    }

    return result;
  }

  // ── Queries ─────────────────────────────────────────────

  bool roomHasActiveCall(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) return false;
    return _getActiveRtcMemberships(room).isNotEmpty;
  }

  List<String> activeCallIdsForRoom(String roomId) {
    final room = _client.getRoomById(roomId);
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
    final room = _client.getRoomById(roomId);
    if (room == null) return 0;
    final memberships = _getActiveRtcMemberships(room);
    return memberships
        .where((m) => (m['call_id'] as String? ?? '') == groupCallId)
        .length;
  }

  List<Map<String, dynamic>> _getActiveRtcMemberships(Room room) {
    final states = room.states[_callMemberEventType];
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

  // ── Incoming Call Handling ─────────────────────────────────

  void _handleCallEnded() {
    if (_joining) {
      _endedDuringJoin = true;
      return;
    }
    if (_callState == LatticeCallState.ringingIncoming ||
        _callState == LatticeCallState.ringingOutgoing) {
      _incomingCall = null;
      _stopRinging();
      _callState = LatticeCallState.idle;
      notifyListeners();
    }
  }

  @visibleForTesting
  void simulateCallEnded() => _handleCallEnded();

  // ── Ringing Actions ────────────────────────────────────────

  void acceptCall({bool withVideo = false}) {
    if (_callState != LatticeCallState.ringingIncoming) return;
    final info = _incomingCall;
    if (info == null) return;

    _incomingCall = null;
    _callState = LatticeCallState.joining;
    _stopRinging();
    notifyListeners();

    unawaited(joinCall(info.roomId));
  }

  void declineCall() {
    if (_callState != LatticeCallState.ringingIncoming) return;
    _incomingCall = null;
    _callState = LatticeCallState.idle;
    _stopRinging();
    notifyListeners();
  }

  void cancelOutgoingCall() {
    if (_callState != LatticeCallState.ringingOutgoing) return;
    _stopRinging();
    if (_joining) {
      _endedDuringJoin = true;
      _callState = LatticeCallState.idle;
      notifyListeners();
    } else {
      _callState = LatticeCallState.idle;
      notifyListeners();
      unawaited(leaveCall());
    }
  }

  Future<void> initiateCall(String roomId, {model.CallType type = model.CallType.voice}) async {
    if (!_initialized) init();
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

  Future<void> joinCall(String roomId) async {
    if (!_initialized) init();

    const allowedStates = {
      LatticeCallState.idle,
      LatticeCallState.joining,
      LatticeCallState.ringingOutgoing,
      LatticeCallState.failed,
    };
    if (!allowedStates.contains(_callState) || _joining) {
      if (_callState != LatticeCallState.idle) {
        _stopRinging();
        _callState = LatticeCallState.failed;
        notifyListeners();
      }
      return;
    }

    final room = _client.getRoomById(roomId);
    if (room == null) {
      if (_callState == LatticeCallState.ringingOutgoing ||
          _callState == LatticeCallState.joining) {
        _stopRinging();
        _callState = LatticeCallState.failed;
        notifyListeners();
      }
      return;
    }

    _joining = true;
    if (_callState != LatticeCallState.ringingOutgoing) {
      _callState = LatticeCallState.joining;
    }
    notifyListeners();

    try {
      if (_cachedLivekitServiceUrl == null) {
        await fetchWellKnownLiveKit();
      }
      if (_cachedLivekitServiceUrl == null) {
        throw Exception('LiveKit service URL not found in well-known');
      }

      final livekitAlias = room.canonicalAlias.isNotEmpty
          ? room.canonicalAlias
          : room.id;

      _activeCallRoomId = roomId;

      await _sendMembershipEvent(roomId, livekitAlias);
      _startMembershipRenewal(roomId, livekitAlias);

      await _connectLiveKit(
        livekitServiceUrl: _cachedLivekitServiceUrl!,
        livekitAlias: livekitAlias,
      );

      _stopRinging();

      if (_endedDuringJoin) {
        debugPrint('[Lattice] Call ended while joining, cleaning up');
        await _cleanupLiveKit();
        await _removeMembershipEvent(roomId);
        _cancelMembershipRenewal();
        _activeCallRoomId = null;
        _callState = LatticeCallState.idle;
        notifyListeners();
        return;
      }

      _callStartTime = DateTime.now();
      _callState = LatticeCallState.connected;
      notifyListeners();
      debugPrint('[Lattice] Joined call in room $roomId');
    } catch (e) {
      debugPrint('[Lattice] Failed to join call: $e');
      await _cleanupLiveKit();

      if (_activeCallRoomId != null) {
        try {
          await _removeMembershipEvent(_activeCallRoomId!);
        } catch (leaveError) {
          debugPrint('[Lattice] Error removing membership after failure: $leaveError');
        }
      }

      _cancelMembershipRenewal();
      _activeCallRoomId = null;
      _stopRinging();

      _callState = LatticeCallState.failed;
      notifyListeners();
    } finally {
      _joining = false;
      _endedDuringJoin = false;
    }
  }

  Future<void> leaveCall() async {
    if (_activeCallRoomId == null) return;

    final roomId = _activeCallRoomId!;
    debugPrint('[Lattice] Leaving call in room $roomId');

    _stopRinging();
    _callState = LatticeCallState.disconnecting;
    notifyListeners();

    await _cleanupLiveKit();
    _cancelMembershipRenewal();

    try {
      await _removeMembershipEvent(roomId);
    } catch (e) {
      debugPrint('[Lattice] Error removing membership: $e');
    }

    _activeCallRoomId = null;
    _callStartTime = null;
    _callState = LatticeCallState.idle;
    notifyListeners();
  }

  // ── Track Toggles ─────────────────────────────────────────

  Future<void> _toggleTrack({
    required bool currentValue,
    required void Function(bool) updateField,
    required Future<void> Function(bool enabled) apply,
    required String label,
  }) async {
    updateField(!currentValue);
    notifyListeners();

    try {
      await apply(!currentValue);
    } catch (e) {
      debugPrint('[Lattice] Failed to toggle $label: $e');
      updateField(currentValue);
      notifyListeners();
    }
  }

  Future<void> toggleMicrophone() async {
    final localParticipant = _livekitRoom?.localParticipant;
    if (localParticipant == null) return;

    await _toggleTrack(
      currentValue: _isMicEnabled,
      updateField: (v) => _isMicEnabled = v,
      label: 'microphone',
      apply: localParticipant.setMicrophoneEnabled,
    );
  }

  Future<void> toggleCamera() async {
    final localParticipant = _livekitRoom?.localParticipant;
    if (localParticipant == null) return;

    await _toggleTrack(
      currentValue: _isCameraEnabled,
      updateField: (v) => _isCameraEnabled = v,
      label: 'camera',
      apply: localParticipant.setCameraEnabled,
    );
  }

  Future<void> toggleScreenShare() async {
    final localParticipant = _livekitRoom?.localParticipant;
    if (localParticipant == null) return;

    await _toggleTrack(
      currentValue: _isScreenShareEnabled,
      updateField: (v) => _isScreenShareEnabled = v,
      label: 'screen share',
      apply: localParticipant.setScreenShareEnabled,
    );
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
    _cancelMembershipRenewal();
    _activeCallRoomId = null;
    _callState = LatticeCallState.idle;
    _initialized = false;
    _incomingCall = null;
    _stopRinging();
    unawaited(_ringtoneService?.dispose());
    _ringtoneService = null;
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
    unawaited(_incomingCallController.close());
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ── MatrixRTC Membership ─────────────────────────────────

  String get _membershipStateKey =>
      '_${_client.userID!}_${_client.deviceID!}_m.call';

  Map<String, dynamic> _makeMembershipContent(
    String livekitServiceUrl,
    String livekitAlias,
  ) => {
    'application': 'm.call',
    'call_id': '',
    'scope': 'm.room',
    'device_id': _client.deviceID,
    'expires': _membershipExpiresMs,
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

  Future<void> _sendMembershipEvent(String roomId, String livekitAlias) async {
    await _client.setRoomStateWithKey(
      roomId,
      _callMemberEventType,
      _membershipStateKey,
      _makeMembershipContent(_cachedLivekitServiceUrl!, livekitAlias),
    );
  }

  Future<void> _removeMembershipEvent(String roomId) async {
    await _client.setRoomStateWithKey(
      roomId,
      _callMemberEventType,
      _membershipStateKey,
      {},
    );
  }

  void _startMembershipRenewal(String roomId, String livekitAlias) {
    _cancelMembershipRenewal();
    _membershipRenewalTimer = Timer.periodic(
      _membershipRenewalInterval,
      (_) => _sendMembershipEvent(roomId, livekitAlias).catchError(
        (Object e) => debugPrint('[Lattice] Failed to renew membership: $e'),
      ),
    );
  }

  void _cancelMembershipRenewal() {
    _membershipRenewalTimer?.cancel();
    _membershipRenewalTimer = null;
  }

  // ── LiveKit Private ─────────────────────────────────────

  Future<http.Response> _postWithRedirects(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    var currentUrl = url;
    var response = await _httpPost(currentUrl, headers: headers, body: body);

    var redirects = 0;
    while ((response.statusCode == 307 || response.statusCode == 308) &&
        redirects < 5) {
      final location = response.headers['location'];
      if (location == null) break;
      currentUrl = currentUrl.resolve(location);
      response = await _httpPost(currentUrl, headers: headers, body: body);
      redirects++;
    }

    return response;
  }

  String _buildServiceUrl(String baseUrl, String path) {
    if (baseUrl.endsWith('/')) return '$baseUrl$path';
    return '$baseUrl/$path';
  }

  Future<({String url, String token})> _fetchLiveKitToken({
    required String livekitServiceUrl,
    required String livekitAlias,
  }) async {
    final openId = await _client.requestOpenIdToken(
      _client.userID!,
      {},
    );

    final openIdPayload = {
      'access_token': openId.accessToken,
      'token_type': openId.tokenType,
      'matrix_server_name': openId.matrixServerName,
      'expires_in': openId.expiresIn,
    };
    final headers = {'Content-Type': 'application/json'};

    final newBody = jsonEncode({
      'room_id': livekitAlias,
      'slot_id': 'm.call#ROOM',
      'openid_token': openIdPayload,
      'member': {
        'id': '${_client.userID}:${_client.deviceID}',
        'claimed_user_id': _client.userID,
        'claimed_device_id': _client.deviceID,
      },
    });

    final newUrl = Uri.parse(
      _buildServiceUrl(livekitServiceUrl, 'get_token'),
    );
    var response = await _postWithRedirects(
      newUrl,
      headers: headers,
      body: newBody,
    );

    if (response.statusCode == 404) {
      final legacyBody = jsonEncode({
        'room': livekitAlias,
        'openid_token': openIdPayload,
        'device_id': _client.deviceID,
      });
      final legacyUrl = Uri.parse(
        _buildServiceUrl(livekitServiceUrl, 'sfu/get'),
      );
      response = await _postWithRedirects(
        legacyUrl,
        headers: headers,
        body: legacyBody,
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        'LiveKit token exchange failed: ${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (url: json['url'] as String, token: json['jwt'] as String? ?? json['token'] as String);
  }

  Future<void> _connectLiveKit({
    required String livekitServiceUrl,
    required String livekitAlias,
  }) async {
    final credentials = await _fetchLiveKitToken(
      livekitServiceUrl: livekitServiceUrl,
      livekitAlias: livekitAlias,
    );

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
      final roomId = _activeCallRoomId;
      _activeCallRoomId = null;
      _cancelMembershipRenewal();
      _callStartTime = null;
      _callState = LatticeCallState.failed;
      notifyListeners();
      if (roomId != null) {
        unawaited(
          _removeMembershipEvent(roomId).catchError(
            (Object e) => debugPrint('[Lattice] Error removing membership after disconnect: $e'),
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

  String? _cachedLivekitServiceUrl;

  @visibleForTesting
  set cachedLivekitServiceUrlForTest(String? url) =>
      _cachedLivekitServiceUrl = url;

  Future<void> fetchWellKnownLiveKit() async {
    try {
      final wellKnown = await _client.getWellknown();
      final fociList =
          wellKnown.additionalProperties['org.matrix.msc4143.rtc_foci'] as List?;
      if (fociList == null || fociList.isEmpty) return;

      for (final foci in fociList) {
        if (foci is Map<String, Object?> && foci['type'] == 'livekit') {
          final serviceUrl = foci['livekit_service_url'] as String?;
          if (serviceUrl != null) {
            _cachedLivekitServiceUrl = serviceUrl;
            debugPrint('[Lattice] LiveKit service URL: $serviceUrl');
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[Lattice] Failed to fetch LiveKit well-known: $e');
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/models/call_participant.dart' as ui;
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';

mixin CallLiveKitMixin on ChangeNotifier {
  // ── Cross-mixin dependencies ──────────────────────────────────
  Client get client;
  LatticeCallState get callState;
  @protected
  set callState(LatticeCallState value);
  String? get activeCallRoomId;
  @protected
  set activeCallRoomId(String? value);
  DateTime? get callStartTime;
  @protected
  set callStartTime(DateTime? value);
  void cancelMembershipRenewal();
  Future<void> removeMembershipEvent(String roomId);

  // ── LiveKit State ─────────────────────────────────────────────
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

  // ── Participant Aggregation ───────────────────────────────────
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

  // ── Track Toggles ─────────────────────────────────────────────
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

  // ── TURN Server ───────────────────────────────────────────────
  Future<TurnServerCredentials?> fetchTurnServers() async {
    try {
      return await client.getTurnServer();
    } catch (e) {
      debugPrint('[Lattice] Failed to fetch TURN servers: $e');
      return null;
    }
  }

  // ── HTTP Helpers ──────────────────────────────────────────────
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
    final openId = await client.requestOpenIdToken(
      client.userID!,
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
        'id': '${client.userID}:${client.deviceID}',
        'claimed_user_id': client.userID,
        'claimed_device_id': client.deviceID,
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
        'device_id': client.deviceID,
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

  // ── Connection ────────────────────────────────────────────────
  @protected
  Future<void> connectLiveKit({
    required String livekitServiceUrl,
    required String livekitAlias,
  }) async {
    final credentials = await _fetchLiveKitToken(
      livekitServiceUrl: livekitServiceUrl,
      livekitAlias: livekitAlias,
    );

    _livekitRoom = _roomFactory();

    await _livekitRoom!.connect(credentials.url, credentials.token);

    _livekitListener = _livekitRoom!.createListener();
    _subscribeLiveKitEvents();

    _isMicEnabled = false;
    _isCameraEnabled = false;
    _isScreenShareEnabled = false;
    _syncParticipants();
  }

  void _subscribeLiveKitEvents() {
    final listener = _livekitListener!;

    listener.on<livekit.RoomReconnectingEvent>((_) {
      callState = LatticeCallState.reconnecting;
      notifyListeners();
    });

    listener.on<livekit.RoomReconnectedEvent>((_) {
      callState = LatticeCallState.connected;
      notifyListeners();
    });

    listener.on<livekit.RoomDisconnectedEvent>((_) {
      final roomId = activeCallRoomId;
      activeCallRoomId = null;
      cancelMembershipRenewal();
      callStartTime = null;
      callState = LatticeCallState.failed;
      notifyListeners();
      unawaited(cleanupLiveKit());
      if (roomId != null) {
        unawaited(
          removeMembershipEvent(roomId).catchError(
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

  @protected
  Future<void> cleanupLiveKit() async {
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
    } catch (e) {
      debugPrint('[Lattice] Error disposing LiveKit listener: $e');
    }
    try {
      await room?.dispose();
    } catch (e) {
      debugPrint('[Lattice] Error disposing LiveKit room: $e');
    }
  }

  // ── Well-Known ────────────────────────────────────────────────
  String? _cachedLivekitServiceUrl;

  String? get cachedLivekitServiceUrl => _cachedLivekitServiceUrl;

  @visibleForTesting
  set cachedLivekitServiceUrlForTest(String? url) =>
      _cachedLivekitServiceUrl = url;

  Future<void> fetchWellKnownLiveKit() async {
    try {
      final wellKnown = await client.getWellknown();
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/core/utils/platform_info.dart';
import 'package:lattice/features/calling/models/call_participant.dart' as ui;
import 'package:lattice/features/calling/models/call_participant_mapper.dart';
import 'package:lattice/features/calling/models/call_state.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';

// ── Types ──────────────────────────────────────────────────

typedef LiveKitRoomFactory = livekit.Room Function();
typedef HttpPostFunction = Future<http.Response> Function(
  http.Client httpClient,
  Uri url, {
  Map<String, String>? headers,
  Object? body,
});

// ── LiveKit Connection Events ──────────────────────────────

sealed class LiveKitConnectionEvent {}

class LiveKitReconnecting extends LiveKitConnectionEvent {}

class LiveKitReconnected extends LiveKitConnectionEvent {}

class LiveKitDisconnected extends LiveKitConnectionEvent {}

// ── LiveKit Service ────────────────────────────────────────

class LiveKitService {
  LiveKitService({
    required Client client,
    required VoidCallback onChanged,
    LiveKitRoomFactory? roomFactory,
    HttpPostFunction? httpPost,
  })  : _client = client,
        _onChanged = onChanged,
        _roomFactory = roomFactory ?? livekit.Room.new,
        httpPostForTest = httpPost ?? _sendNoAutoRedirect;

  static const _maxRedirects = 6;
  static const _wellKnownTtl = Duration(hours: 1);

  Client _client;
  final VoidCallback _onChanged;
  LiveKitRoomFactory _roomFactory;
  HttpPostFunction httpPostForTest;

  void updateClient(Client client) => _client = client;

  set roomFactoryForTest(LiveKitRoomFactory factory) => _roomFactory = factory;

  // ── LiveKit State ──────────────────────────────────────────

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

  List<ui.CallParticipant>? _cachedParticipants;
  String? _cachedParticipantsRoomId;
  bool _participantsDirty = true;

  final _connectionEventController =
      StreamController<LiveKitConnectionEvent>.broadcast();

  Stream<LiveKitConnectionEvent> get connectionEvents =>
      _connectionEventController.stream;

  // ── Participant Aggregation ────────────────────────────────

  List<ui.CallParticipant> allParticipants({
    required String? activeCallRoomId,
  }) {
    if (_participantsDirty ||
        _cachedParticipants == null ||
        _cachedParticipantsRoomId != activeCallRoomId) {
      _cachedParticipants = _buildParticipantList(activeCallRoomId);
      _cachedParticipantsRoomId = activeCallRoomId;
      _participantsDirty = false;
    }
    return _cachedParticipants!;
  }

  void _invalidateParticipants() => _participantsDirty = true;

  List<ui.CallParticipant> _buildParticipantList(String? activeCallRoomId) {
    final result = <ui.CallParticipant>[];
    if (_livekitRoom == null) return result;

    final room =
        activeCallRoomId != null ? _client.getRoomById(activeCallRoomId) : null;

    Uri? avatarFor(String matrixId) {
      if (room == null) return null;
      return room.unsafeGetUserFromMemoryOrFallback(matrixId).avatarUrl;
    }

    final local = _livekitRoom!.localParticipant;
    if (local != null) {
      final localId = CallParticipantMapper.extractMatrixId(local.identity);
      result.add(
        CallParticipantMapper.fromLiveKit(
          local,
          activeSpeakers: _activeSpeakers,
          isLocal: true,
          avatarUrl: avatarFor(localId),
        ),
      );
    }
    for (final p in _participants) {
      final pId = CallParticipantMapper.extractMatrixId(p.identity);
      result.add(
        CallParticipantMapper.fromLiveKit(
          p,
          activeSpeakers: _activeSpeakers,
          avatarUrl: avatarFor(pId),
        ),
      );
    }

    return result;
  }

  // ── Track Toggles ──────────────────────────────────────────

  Future<void> _toggleTrack({
    required bool currentValue,
    required void Function(bool) updateField,
    required Future<void> Function(bool enabled) apply,
    required String label,
  }) async {
    updateField(!currentValue);
    _onChanged();

    try {
      await apply(!currentValue);
    } catch (e) {
      debugPrint('[Lattice] Failed to toggle $label: $e');
      updateField(currentValue);
      _onChanged();
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

  Future<void> toggleScreenShare({String? sourceId}) async {
    final localParticipant = _livekitRoom?.localParticipant;
    if (localParticipant == null) return;

    final willEnable = !_isScreenShareEnabled;

    if (isNativeAndroid && willEnable) {
      await _startAndroidMediaProjectionService();
    }

    final options = sourceId != null
        ? livekit.ScreenShareCaptureOptions(sourceId: sourceId)
        : null;

    await _toggleTrack(
      currentValue: _isScreenShareEnabled,
      updateField: (v) => _isScreenShareEnabled = v,
      label: 'screen share',
      apply: (enabled) => localParticipant.setScreenShareEnabled(
        enabled,
        captureScreenAudio: true,
        screenShareCaptureOptions: options,
      ),
    );

    if (isNativeAndroid && !_isScreenShareEnabled) {
      await _stopAndroidMediaProjectionService();
    }
  }

  static const _androidBgConfig = FlutterBackgroundAndroidConfig(
    notificationTitle: 'Lattice',
    notificationText: 'Sharing screen',
  );

  Future<void> _startAndroidMediaProjectionService() async {
    try {
      await FlutterBackground.initialize(androidConfig: _androidBgConfig);
      await FlutterBackground.enableBackgroundExecution();
    } catch (e) {
      debugPrint('[Lattice] Failed to start media projection service: $e');
    }
  }

  Future<void> _stopAndroidMediaProjectionService() async {
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (e) {
      debugPrint('[Lattice] Failed to stop media projection service: $e');
    }
  }

  // ── HTTP Helpers ───────────────────────────────────────────

  static Future<http.Response> _sendNoAutoRedirect(
    http.Client httpClient,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final request = http.Request('POST', url)..followRedirects = false;
    if (headers != null) request.headers.addAll(headers);
    if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body is String) {
      request.bodyBytes = utf8.encode(body);
    }
    return http.Response.fromStream(await httpClient.send(request));
  }

  Future<http.Response> _postWithRedirects(
    Uri url, {
    required Map<String, String> headers,
    required Object body,
  }) async {
    final httpClient = http.Client();
    try {
      var currentUrl = url;

      for (var i = 0; i < _maxRedirects; i++) {
        final response = await httpPostForTest(
          httpClient,
          currentUrl,
          headers: headers,
          body: body,
        );
        final code = response.statusCode;

        if (code == 301 ||
            code == 302 ||
            code == 303 ||
            code == 307 ||
            code == 308) {
          final location = response.headers['location'];
          if (location == null) return response;
          currentUrl = currentUrl.resolve(location);
          continue;
        }

        return response;
      }

      throw Exception('Too many redirects');
    } finally {
      httpClient.close();
    }
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

    final headers = {'Content-Type': 'application/json'};
    final openIdPayload = {
      'access_token': openId.accessToken,
      'token_type': openId.tokenType,
      'matrix_server_name': openId.matrixServerName,
      'expires_in': openId.expiresIn,
    };

    final url = Uri.parse(
      _buildServiceUrl(livekitServiceUrl, 'sfu/get'),
    );
    final response = await _postWithRedirects(
      url,
      headers: headers,
      body: utf8.encode(
        jsonEncode({
          'room': livekitAlias,
          'openid_token': openIdPayload,
          'device_id': _client.deviceID,
        }),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'LiveKit token exchange failed: ${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      url: json['url'] as String,
      token: json['jwt'] as String? ?? json['token'] as String,
    );
  }

  // ── Connection ─────────────────────────────────────────────

  Future<void> connectLiveKit({
    required String livekitServiceUrl,
    required String livekitAlias,
    required LatticeCallState Function() currentState,
  }) async {
    final credentials = await _fetchLiveKitToken(
      livekitServiceUrl: livekitServiceUrl,
      livekitAlias: livekitAlias,
    );

    if (currentState() != LatticeCallState.joining) return;

    _livekitRoom = _roomFactory();

    await _livekitRoom!.connect(credentials.url, credentials.token);

    if (currentState() != LatticeCallState.joining) {
      await cleanupLiveKit();
      return;
    }

    _livekitListener = _livekitRoom!.createListener();
    _subscribeLiveKitEvents();

    await _livekitRoom!.localParticipant?.setMicrophoneEnabled(true);
    _isMicEnabled = true;
    _isCameraEnabled = false;
    _isScreenShareEnabled = false;
    _syncParticipants();
  }

  void _subscribeLiveKitEvents() {
    final listener = _livekitListener!;

    listener.on<livekit.RoomReconnectingEvent>((_) {
      _connectionEventController.add(LiveKitReconnecting());
    });

    listener.on<livekit.RoomReconnectedEvent>((_) {
      _connectionEventController.add(LiveKitReconnected());
    });

    listener.on<livekit.RoomDisconnectedEvent>((_) {
      _connectionEventController.add(LiveKitDisconnected());
    });

    listener.on<livekit.ParticipantConnectedEvent>((_) {
      _syncParticipants();
      _invalidateParticipants();
      _onChanged();
    });

    listener.on<livekit.ParticipantDisconnectedEvent>((_) {
      _syncParticipants();
      _invalidateParticipants();
      _onChanged();
    });

    listener.on<livekit.ActiveSpeakersChangedEvent>((event) {
      _activeSpeakers = event.speakers.toList();
      _invalidateParticipants();
      _onChanged();
    });

    listener.on<livekit.TrackMutedEvent>((_) {
      _invalidateParticipants();
      _onChanged();
    });
    listener.on<livekit.TrackUnmutedEvent>((_) {
      _invalidateParticipants();
      _onChanged();
    });
    listener.on<livekit.TrackSubscribedEvent>((_) {
      _invalidateParticipants();
      _onChanged();
    });
    listener.on<livekit.TrackUnsubscribedEvent>((_) {
      _invalidateParticipants();
      _onChanged();
    });
    listener.on<livekit.LocalTrackPublishedEvent>((_) {
      _invalidateParticipants();
      _onChanged();
    });
    listener.on<livekit.LocalTrackUnpublishedEvent>((_) {
      _invalidateParticipants();
      _onChanged();
    });
  }

  void _syncParticipants() {
    _participants = _livekitRoom?.remoteParticipants.values.toList() ?? [];
  }

  Future<void> cleanupLiveKit() async {
    final listener = _livekitListener;
    final room = _livekitRoom;
    _livekitListener = null;
    _livekitRoom = null;
    _participants = [];
    _activeSpeakers = [];
    _cachedParticipants = null;
    _cachedParticipantsRoomId = null;
    _participantsDirty = true;
    _isMicEnabled = false;
    _isCameraEnabled = false;
    _isScreenShareEnabled = false;

    try {
      await listener?.dispose();
    } catch (e) {
      debugPrint('[Lattice] Error disconnecting LiveKit: $e');
    }
    try {
      await room?.disconnect();
    } catch (e) {
      debugPrint('[Lattice] Error disposing LiveKit listener: $e');
    }
    try {
      await room?.dispose();
    } catch (e) {
      debugPrint('[Lattice] Error disposing LiveKit room: $e');
    }
  }

  // ── Well-Known ─────────────────────────────────────────────

  String? _cachedLivekitServiceUrl;
  DateTime? _wellKnownFetchedAt;

  String? get cachedLivekitServiceUrl {
    if (_cachedLivekitServiceUrl != null &&
        _wellKnownFetchedAt != null &&
        DateTime.now().difference(_wellKnownFetchedAt!) > _wellKnownTtl) {
      _cachedLivekitServiceUrl = null;
      _wellKnownFetchedAt = null;
    }
    return _cachedLivekitServiceUrl;
  }

  set cachedLivekitServiceUrlForTest(String? url) {
    _cachedLivekitServiceUrl = url;
    _wellKnownFetchedAt = url != null ? DateTime.now() : null;
  }

  Future<void> fetchWellKnownLiveKit() async {
    try {
      final wellKnown = await _client.getWellknown();
      final fociList = wellKnown
          .additionalProperties['org.matrix.msc4143.rtc_foci'] as List?;
      if (fociList == null || fociList.isEmpty) return;

      for (final foci in fociList) {
        if (foci is Map<String, Object?> && foci['type'] == 'livekit') {
          final serviceUrl = foci['livekit_service_url'] as String?;
          if (serviceUrl != null) {
            _cachedLivekitServiceUrl = serviceUrl;
            _wellKnownFetchedAt = DateTime.now();
            _onChanged();
            debugPrint('[Lattice] LiveKit service URL: $serviceUrl');
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[Lattice] Failed to fetch LiveKit well-known: $e');
    }
  }

  void dispose() {
    unawaited(_connectionEventController.close());
  }
}

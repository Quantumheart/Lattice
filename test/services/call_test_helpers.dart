import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/calling/services/native_call_ui_service.dart';
import 'package:kohera/features/calling/services/ringtone_service.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:matrix/matrix.dart';

// ── LiveKit Fakes ─────────────────────────────────────────

class FakeLocalParticipant extends Fake implements livekit.LocalParticipant {
  bool micEnabled = false;
  bool cameraEnabled = false;
  bool screenShareEnabled = false;
  bool throwOnToggle = false;

  @override
  List<livekit.LocalTrackPublication<livekit.LocalVideoTrack>>
      get videoTrackPublications => [];

  @override
  String get identity => 'local';

  @override
  String get name => 'Local User';

  @override
  bool get isMuted => false;

  @override
  double get audioLevel => 0;

  @override
  Future<livekit.LocalTrackPublication?> setMicrophoneEnabled(
    bool enabled, {
    livekit.AudioCaptureOptions? audioCaptureOptions,
  }) async {
    if (throwOnToggle) throw Exception('mic error');
    micEnabled = enabled;
    return null;
  }

  @override
  Future<livekit.LocalTrackPublication?> setCameraEnabled(
    bool enabled, {
    livekit.CameraCaptureOptions? cameraCaptureOptions,
  }) async {
    if (throwOnToggle) throw Exception('camera error');
    cameraEnabled = enabled;
    return null;
  }

  @override
  Future<livekit.LocalTrackPublication?> setScreenShareEnabled(
    bool enabled, {
    bool? captureScreenAudio,
    livekit.ScreenShareCaptureOptions? screenShareCaptureOptions,
  }) async {
    if (throwOnToggle) throw Exception('screenshare error');
    screenShareEnabled = enabled;
    return null;
  }
}

class FakeEventsListener<T> extends Fake implements livekit.EventsListener<T> {
  final _handlers = <Type, List<Function>>{};
  bool throwOnDispose = false;

  @override
  livekit.CancelListenFunc on<E>(
    FutureOr<void> Function(E) then, {
    bool Function(E)? filter,
  }) {
    _handlers.putIfAbsent(E, () => []).add(then);
    return () async {};
  }

  @override
  Future<bool> dispose() async {
    if (throwOnDispose) throw Exception('listener dispose error');
    _handlers.clear();
    return true;
  }

  void fire<E>(E event) {
    final handlers = _handlers[E];
    if (handlers != null) {
      for (final handler in handlers) {
        (handler as void Function(E))(event);
      }
    }
  }
}

class FakeLiveKitRoom extends Fake implements livekit.Room {
  FakeLocalParticipant? localParticipantFake;
  final Map<String, livekit.RemoteParticipant> remoteParticipantsMap = {};
  FakeEventsListener<livekit.RoomEvent>? listener;
  bool connected = false;
  bool disconnected = false;
  bool disposed = false;
  bool throwOnConnect = false;
  bool throwOnDisconnect = false;
  bool throwOnDispose = false;

  @override
  livekit.LocalParticipant? get localParticipant => localParticipantFake;

  @override
  UnmodifiableMapView<String, livekit.RemoteParticipant>
      get remoteParticipants => UnmodifiableMapView(remoteParticipantsMap);

  @override
  livekit.EventsListener<livekit.RoomEvent> createListener({
    bool synchronized = false,
  }) {
    listener = FakeEventsListener<livekit.RoomEvent>();
    return listener!;
  }

  @override
  Future<void> connect(
    String url,
    String token, {
    livekit.ConnectOptions? connectOptions,
    livekit.RoomOptions? roomOptions,
    livekit.FastConnectOptions? fastConnectOptions,
  }) async {
    if (throwOnConnect) throw Exception('connect failed');
    connected = true;
    localParticipantFake = FakeLocalParticipant();
  }

  @override
  Future<void> disconnect() async {
    if (throwOnDisconnect) throw Exception('disconnect error');
    disconnected = true;
  }

  @override
  Future<bool> dispose() async {
    if (throwOnDispose) throw Exception('dispose error');
    disposed = true;
    return true;
  }
}

class FakeRemoteParticipant extends Fake implements livekit.RemoteParticipant {
  FakeRemoteParticipant({this.identity = 'remote', this.name = 'Remote User'});

  @override
  List<livekit.RemoteTrackPublication<livekit.RemoteVideoTrack>>
      get videoTrackPublications => [];

  @override
  final String identity;

  @override
  final String name;

  @override
  bool get isMuted => false;

  @override
  double get audioLevel => 0;
}

// ── LiveKit Track/Publication Fakes ───────────────────────

class FakeTrackPublication extends Fake implements livekit.TrackPublication {}

class FakeLocalTrackPublication extends Fake
    implements livekit.LocalTrackPublication {}

class FakeRemoteTrackPublication extends Fake
    implements livekit.RemoteTrackPublication {}

class FakeTrack extends Fake implements livekit.Track {}

// ── Fake User ─────────────────────────────────────────────

class FakeUser extends Fake implements User {
  FakeUser({this.displayName, this.avatarUrl});

  @override
  final String? displayName;

  @override
  final Uri? avatarUrl;

  @override
  String calcDisplayname({
    bool? formatLocalpart,
    bool? mxidLocalPartFallback,
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  }) =>
      displayName ?? 'Unknown';
}

// ── Fake Event for room state testing ─────────────────────

class FakeEvent extends Fake implements Event {
  FakeEvent({
    required this.content,
    required int originServerTs,
    this.type = '',
    this.roomId,
    this.senderId = '',
    Room? room,
    User? senderFromMemoryOrFallback,
  })  : _room = room,
        _sender = senderFromMemoryOrFallback,
        originServerTs = DateTime.fromMillisecondsSinceEpoch(originServerTs);

  @override
  final Map<String, dynamic> content;

  @override
  final DateTime originServerTs;

  @override
  final String type;

  @override
  final String? roomId;

  @override
  final String senderId;

  final Room? _room;
  final User? _sender;

  @override
  Room get room => _room!;

  @override
  User get senderFromMemoryOrFallback => _sender ?? FakeUser();
}

// ── Fake Native Call UI Service ───────────────────────────

class FakeNativeCallUiService extends Fake implements NativeCallUiService {
  int showIncomingCalls = 0;
  int showOutgoingCalls = 0;
  int attachExistingCalls = 0;
  int endNativeCalls = 0;
  int updateConnectedCalls = 0;
  String? lastAttachedCallId;

  final _actions = StreamController<NativeCallAction>.broadcast();
  final _nativeAccepted = StreamController<String>.broadcast();

  @override
  Stream<NativeCallAction> get actions => _actions.stream;

  @override
  Stream<String> get nativeAcceptedCallStream => _nativeAccepted.stream;

  @override
  void init({required String Function() getCallState}) {}

  @override
  void showNativeIncomingCall({
    required String? callId,
    required String roomId,
    required String callerName,
    required Uri? callerAvatarUrl,
    required bool isVideo,
  }) {
    showIncomingCalls++;
  }

  @override
  void showNativeOutgoingCall(String roomId, String callerName, bool isVideo) {
    showOutgoingCalls++;
  }

  @override
  void attachExistingNativeCall(String nativeCallId) {
    attachExistingCalls++;
    lastAttachedCallId = nativeCallId;
  }

  @override
  void updateNativeCallConnected() {
    updateConnectedCalls++;
  }

  @override
  void endNativeCall() {
    endNativeCalls++;
  }

  @override
  void dispose() {
    unawaited(_actions.close());
    unawaited(_nativeAccepted.close());
  }
}

// ── Fake Ringtone Service ─────────────────────────────────

class FakeRingtoneService extends Fake implements RingtoneService {
  bool playing = false;
  String? lastPlayed;
  bool disposed = false;
  bool stopped = false;

  @override
  Future<void> playRingtone({bool loop = true}) async {
    playing = true;
    lastPlayed = 'ringtone';
  }

  @override
  Future<void> playDialtone({bool loop = true}) async {
    playing = true;
    lastPlayed = 'dialtone';
  }

  @override
  Future<void> stop() async {
    playing = false;
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    playing = false;
  }
}

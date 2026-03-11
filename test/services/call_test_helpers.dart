import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
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
    disconnected = true;
  }

  @override
  Future<bool> dispose() async {
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

// ── Fake Event for room state testing ─────────────────────

class FakeEvent extends Fake implements Event {
  FakeEvent({required this.content, required int originServerTs})
      : originServerTs = DateTime.fromMillisecondsSinceEpoch(originServerTs);

  @override
  final Map<String, dynamic> content;

  @override
  final DateTime originServerTs;
}

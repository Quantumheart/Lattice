import 'dart:async';
import 'dart:math';

import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:lattice/core/utils/platform_info.dart';

// coverage:ignore-start

// ── Native Call Actions ────────────────────────────────────

sealed class NativeCallAction {}

class NativeCallAccepted extends NativeCallAction {
  NativeCallAccepted({this.roomId, this.withVideo = false});
  final String? roomId;
  final bool withVideo;
}

class NativeCallDeclined extends NativeCallAction {}

class NativeCallEnded extends NativeCallAction {}

class NativeCallTimedOut extends NativeCallAction {}

// ── Native Call UI Service ─────────────────────────────────

class NativeCallUiService {
  static final _random = Random();

  static String _generateUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    return '${bytes.sublist(0, 4).map(hex).join()}-'
        '${bytes.sublist(4, 6).map(hex).join()}-'
        '${bytes.sublist(6, 8).map(hex).join()}-'
        '${bytes.sublist(8, 10).map(hex).join()}-'
        '${bytes.sublist(10, 16).map(hex).join()}';
  }

  String? _nativeCallId;
  StreamSubscription<CallEvent?>? _nativeEventSub;
  bool _endingFromFlutter = false;

  final _actionController = StreamController<NativeCallAction>.broadcast();
  Stream<NativeCallAction> get actions => _actionController.stream;

  final StreamController<String> _nativeAcceptedCallController =
      StreamController<String>.broadcast();

  Stream<String> get nativeAcceptedCallStream =>
      _nativeAcceptedCallController.stream;

  bool get _isMobile => isNativeMobile;

  void init({
    required String Function() getCallState,
  }) {
    if (!_isMobile) return;
    _getCallState = getCallState;
    _nativeEventSub = FlutterCallkitIncoming.onEvent.listen(_onNativeEvent);
    unawaited(_checkPendingAccept());
  }

  String Function() _getCallState = () => 'idle';

  Future<void> _checkPendingAccept() async {
    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls is List && activeCalls.isNotEmpty) {
      final call = activeCalls.last;
      if (call is Map && call['isAccepted'] == true) {
        final extra = (call['extra'] as Map?)?.cast<String, dynamic>();
        final roomId = extra?['roomId'] as String?;
        final withVideo = extra?['withVideo'] == 'true';
        if (roomId != null) {
          _actionController.add(
            NativeCallAccepted(roomId: roomId, withVideo: withVideo),
          );
          _nativeAcceptedCallController.add(roomId);
        }
      }
    }
  }

  void showNativeIncomingCall({
    required String? callId,
    required String roomId,
    required String callerName,
    required Uri? callerAvatarUrl,
    required bool isVideo,
  }) {
    if (!_isMobile) return;
    _nativeCallId = _generateUuid();
    final params = CallKitParams(
      id: _nativeCallId,
      nameCaller: callerName,
      avatar: callerAvatarUrl?.toString(),
      type: isVideo ? 1 : 0,
      duration: 60000,
      extra: {'roomId': roomId, 'withVideo': isVideo.toString()},
      android: const AndroidParams(isShowFullLockedScreen: true),
      ios: const IOSParams(supportsVideo: true, configureAudioSession: false),
    );
    unawaited(FlutterCallkitIncoming.showCallkitIncoming(params));
  }

  void showNativeOutgoingCall(String roomId, String callerName, bool isVideo) {
    if (!_isMobile) return;
    _nativeCallId = _generateUuid();
    final params = CallKitParams(
      id: _nativeCallId,
      nameCaller: callerName,
      type: isVideo ? 1 : 0,
      extra: {'roomId': roomId, 'withVideo': isVideo.toString()},
      android: const AndroidParams(isShowFullLockedScreen: true),
      ios: const IOSParams(supportsVideo: true, configureAudioSession: false),
    );
    unawaited(FlutterCallkitIncoming.startCall(params));
  }

  void updateNativeCallConnected() {
    if (!_isMobile || _nativeCallId == null) return;
    unawaited(FlutterCallkitIncoming.setCallConnected(_nativeCallId!));
  }

  void endNativeCall() {
    if (!_isMobile || _nativeCallId == null) return;
    _endingFromFlutter = true;
    unawaited(
      FlutterCallkitIncoming.endCall(_nativeCallId!).whenComplete(() {
        _endingFromFlutter = false;
      }),
    );
    _nativeCallId = null;
  }

  void _onNativeEvent(CallEvent? event) {
    if (event == null) return;
    final body = event.body as Map<String, dynamic>?;
    switch (event.event) {
      case Event.actionCallAccept:
        _onNativeAccept(body);
      case Event.actionCallDecline:
        _actionController.add(NativeCallDeclined());
      case Event.actionCallEnded:
        if (!_endingFromFlutter) {
          final callState = _getCallState();
          if (callState == 'connected' || callState == 'reconnecting') {
            _actionController.add(NativeCallEnded());
          }
        }
      case Event.actionCallTimeout:
        _actionController.add(NativeCallTimedOut());
      default:
        break;
    }
  }

  void _onNativeAccept(Map<String, dynamic>? body) {
    final extra = (body?['extra'] as Map?)?.cast<String, dynamic>();
    final roomId = extra?['roomId'] as String?;
    final withVideo = extra?['withVideo'] == 'true';
    _actionController.add(
      NativeCallAccepted(roomId: roomId, withVideo: withVideo),
    );
    if (roomId != null) {
      _nativeAcceptedCallController.add(roomId);
    }
  }

  void dispose() {
    if (_isMobile) {
      unawaited(_nativeEventSub?.cancel());
      _nativeEventSub = null;
      unawaited(FlutterCallkitIncoming.endAllCalls());
      _nativeCallId = null;
    }
    unawaited(_actionController.close());
    unawaited(_nativeAcceptedCallController.close());
  }
}

// coverage:ignore-end

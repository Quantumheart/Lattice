import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/models/incoming_call_info.dart' as model;

mixin CallNativeUiMixin on ChangeNotifier {
  // ── Cross-mixin dependencies ──────────────────────────────────
  LatticeCallState get callState;
  String? get activeCallRoomId;
  void acceptCall({bool withVideo});
  void declineCall();
  Future<void> leaveCall();

  // ── State ─────────────────────────────────────────────────────
  String? _nativeCallId;
  StreamSubscription<CallEvent?>? _nativeEventSub;
  bool _endingFromFlutter = false;

  final StreamController<String> _nativeAcceptedCallController =
      StreamController<String>.broadcast();

  Stream<String> get nativeAcceptedCallStream =>
      _nativeAcceptedCallController.stream;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // ── Lifecycle ─────────────────────────────────────────────────
  @protected
  void initNativeCallUi() {
    if (!_isMobile) return;
    _nativeEventSub = FlutterCallkitIncoming.onEvent.listen(_onNativeEvent);
    unawaited(_checkPendingAccept());
  }

  @protected
  void disposeNativeCallUi() {
    if (!_isMobile) return;
    unawaited(_nativeEventSub?.cancel());
    _nativeEventSub = null;
    unawaited(FlutterCallkitIncoming.endAllCalls());
    _nativeCallId = null;
    unawaited(_nativeAcceptedCallController.close());
  }

  Future<void> _checkPendingAccept() async {
    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls is List && activeCalls.isNotEmpty) {
      final call = activeCalls.last;
      if (call is Map && call['isAccepted'] == true) {
        final extra = call['extra'] as Map<String, dynamic>?;
        final roomId = extra?['roomId'] as String?;
        final withVideo = extra?['withVideo'] == 'true';
        if (roomId != null) {
          acceptCall(withVideo: withVideo);
          _nativeAcceptedCallController.add(roomId);
        }
      }
    }
  }

  // ── Native UI triggers ────────────────────────────────────────
  @protected
  void showNativeIncomingCall(model.IncomingCallInfo info) {
    if (!_isMobile) return;
    _nativeCallId = info.callId ?? info.roomId;
    final params = CallKitParams(
      id: _nativeCallId,
      nameCaller: info.callerName,
      avatar: info.callerAvatarUrl?.toString(),
      type: info.isVideo ? 1 : 0,
      duration: 60000,
      extra: {'roomId': info.roomId, 'withVideo': info.isVideo.toString()},
      android: const AndroidParams(isShowFullLockedScreen: true),
      ios: const IOSParams(supportsVideo: true, configureAudioSession: false),
    );
    unawaited(FlutterCallkitIncoming.showCallkitIncoming(params));
  }

  @protected
  void showNativeOutgoingCall(String roomId, String callerName, bool isVideo) {
    if (!_isMobile) return;
    _nativeCallId = roomId;
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

  @protected
  void updateNativeCallConnected() {
    if (!_isMobile || _nativeCallId == null) return;
    unawaited(FlutterCallkitIncoming.setCallConnected(_nativeCallId!));
  }

  @protected
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

  // ── Native event handling ─────────────────────────────────────
  void _onNativeEvent(CallEvent? event) {
    if (event == null) return;
    final body = event.body as Map<String, dynamic>?;
    switch (event.event) {
      case Event.actionCallAccept:
        _onNativeAccept(body);
      case Event.actionCallDecline:
        declineCall();
      case Event.actionCallEnded:
        if (!_endingFromFlutter) {
          if (callState == LatticeCallState.connected ||
              callState == LatticeCallState.reconnecting) {
            unawaited(leaveCall());
          }
        }
      case Event.actionCallTimeout:
        declineCall();
      default:
        break;
    }
  }

  void _onNativeAccept(Map<String, dynamic>? body) {
    final extra = body?['extra'] as Map<String, dynamic>?;
    final roomId = extra?['roomId'] as String?;
    final withVideo = extra?['withVideo'] == 'true';
    acceptCall(withVideo: withVideo);
    if (roomId != null) {
      _nativeAcceptedCallController.add(roomId);
    }
  }
}

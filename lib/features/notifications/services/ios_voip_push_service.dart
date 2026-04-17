import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/notifications/services/notification_service.dart';
import 'package:matrix/matrix.dart';

const iosVoipMethodChannel = MethodChannel('kohera/voip');

class IosVoipPushService {
  IosVoipPushService({
    required this.matrixService,
    required this.preferencesService,
    required this.notificationService,
    required this.callService,
    bool Function()? platformCheck,
  }) : _isPlatformSupported = platformCheck ?? (() => isNativeIOS);

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final NotificationService notificationService;
  final CallService callService;
  final bool Function() _isPlatformSupported;

  String? _currentToken;
  bool _initialized = false;
  bool _disposed = false;

  static const MethodChannel _channel = iosVoipMethodChannel;
  static const String _appId = NotificationChannel.voipAppId;

  // ── Initialization ───────────────────────────────────────────

  Future<void> init() async {
    if (!_isPlatformSupported()) return;
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleMethodCall);
    debugPrint('[Kohera] IosVoipPushService initialized');
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onVoipToken':
        await onVoipToken(call.arguments as String);
      case 'onVoipTokenInvalidated':
        await onVoipTokenInvalidated();
      case 'onVoipMessage':
        final payload = Map<String, dynamic>.from(call.arguments as Map);
        await onVoipMessage(payload);
    }
  }

  // ── Native callbacks ─────────────────────────────────────────

  Future<void> onVoipToken(String token) async {
    debugPrint(
      '[Kohera] VoIP token received: ${token.substring(0, token.length.clamp(0, 8))}...',
    );
    _currentToken = token;
    await _registerPusher(token);
  }

  Future<void> onVoipTokenInvalidated() async {
    debugPrint('[Kohera] VoIP token invalidated');
    await _unregisterPusher();
    _currentToken = null;
  }

  Future<void> onVoipMessage(Map<String, dynamic> payload) async {
    if (_disposed) return;

    try {
      final notification = (payload['notification'] is Map)
          ? Map<String, dynamic>.from(payload['notification'] as Map)
          : payload;

      final roomId = notification['room_id'] as String?;
      if (roomId == null) return;

      final callId = notification['call_id'] as String?;
      final senderDisplayName =
          (notification['sender_display_name'] as String?) ?? 'Unknown';
      final isVideoRaw = notification['is_video'];
      final isVideo = switch (isVideoRaw) {
        true => true,
        'true' => true,
        1 => true,
        '1' => true,
        _ => false,
      };
      final nativeCallId = payload['nativeCallId'] as String?;
      final callKitAlreadyShown = payload['callKitAlreadyShown'] == true;

      if (nativeCallId != null) {
        callService.attachPrePresentedCallKit(nativeCallId: nativeCallId);
      }
      callService.handlePushCallInvite(
        roomId: roomId,
        callId: callId,
        callerName: senderDisplayName,
        isVideo: isVideo,
        callKitAlreadyShown: callKitAlreadyShown,
      );

      try {
        await matrixService.client.oneShotSync();
      } catch (e) {
        debugPrint('[Kohera] VoIP oneShotSync failed: $e');
        return;
      }

      if (callId != null) {
        await _maybeEndCallFromHangup(roomId, callId);
      }
    } catch (e) {
      debugPrint('[Kohera] VoIP push message processing error: $e');
    }
  }

  // ── Registration ─────────────────────────────────────────────

  Future<void> register() async {
    if (!_isPlatformSupported()) return;
    if (!preferencesService.apnsPushEnabled) return;
    if (!AppConfig.instance.apnsPushConfigured) return;

    try {
      await _channel.invokeMethod<void>('requestVoipToken');
      debugPrint('[Kohera] VoIP registration requested');
    } on PlatformException catch (e) {
      debugPrint('[Kohera] VoIP registration failed: ${e.message}');
    }
  }

  Future<void> unregister() async {
    if (!_isPlatformSupported()) return;
    try {
      await _unregisterPusher();
    } catch (e) {
      debugPrint('[Kohera] Failed to unregister VoIP pusher: $e');
    }
    try {
      await _channel.invokeMethod<void>('unregisterVoip');
    } catch (e) {
      debugPrint('[Kohera] Failed to unregister VoIP: $e');
    }
    _currentToken = null;
    callService.setVoipPushHandlesCallKit(false);
    debugPrint('[Kohera] VoIP unregistered');
  }

  // ── Pusher registration ──────────────────────────────────────

  Future<void> _registerPusher(String token) async {
    if (_disposed) return;
    final client = matrixService.client;
    if (client.userID == null) return;

    final gatewayUrl = _gatewayUrl;
    if (gatewayUrl == null) return;

    try {
      await client.postPusher(
        Pusher(
          appId: _appId,
          pushkey: token,
          appDisplayName: NotificationChannel.appName,
          deviceDisplayName:
              client.deviceName ?? NotificationChannel.iosDefaultDeviceName,
          kind: 'http',
          lang: NotificationChannel.defaultLang,
          data: PusherData(
            url: Uri.parse(gatewayUrl),
          ),
          profileTag: client.deviceID,
        ),
        append: true,
      );
      callService.setVoipPushHandlesCallKit(true);
      debugPrint('[Kohera] VoIP pusher registered with gateway $gatewayUrl');
    } catch (e) {
      debugPrint('[Kohera] Failed to register VoIP pusher: $e');
    }
  }

  Future<void> _unregisterPusher() async {
    final token = _currentToken;
    if (token == null) return;

    final client = matrixService.client;
    await client.deletePusher(
      PusherId(appId: _appId, pushkey: token),
    );
    debugPrint('[Kohera] VoIP pusher unregistered from homeserver');
  }

  // ── Hangup race check ────────────────────────────────────────

  Future<void> _maybeEndCallFromHangup(String roomId, String callId) async {
    if (_disposed) return;
    final client = matrixService.client;
    final room = client.getRoomById(roomId);
    if (room == null) return;

    try {
      final timeline = await room.getTimeline(limit: 20);
      try {
        for (final event in timeline.events) {
          if (event.type == kCallHangup &&
              event.content['call_id'] == callId) {
            if (callService.callState == KoheraCallState.ringingIncoming) {
              callService.endCallFromPushKit();
            }
            return;
          }
        }
      } finally {
        timeline.cancelSubscriptions();
      }
    } catch (e) {
      debugPrint('[Kohera] VoIP hangup scan failed: $e');
    }
  }

  // ── Gateway resolution ───────────────────────────────────────

  String? get _gatewayUrl => AppConfig.instance.apnsPushGatewayUrl;

  // ── Lifecycle ────────────────────────────────────────────────

  void dispose() {
    _disposed = true;
    _initialized = false;
    _channel.setMethodCallHandler(null);
  }
}

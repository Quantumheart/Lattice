import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lattice/core/services/app_config.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/utils/platform_info.dart';
import 'package:lattice/features/notifications/models/notification_constants.dart';
import 'package:lattice/features/notifications/services/notification_service.dart';
import 'package:matrix/matrix.dart';

class ApnsPushService {
  ApnsPushService({
    required this.matrixService,
    required this.preferencesService,
    required this.notificationService,
    required this.callService,
  });

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final NotificationService notificationService;
  final CallService callService;

  String? _currentToken;
  bool _initialized = false;
  bool _disposed = false;

  static const _channel = MethodChannel('lattice/apns');
  static const String _appId = NotificationChannel.appId;

  // ── Initialization ───────────────────────────────────────────

  Future<void> init() async {
    if (!isNativeIOS) return;
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleMethodCall);
    debugPrint('[Lattice] ApnsPushService initialized');
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onToken':
        final token = call.arguments as String;
        debugPrint(
          '[Lattice] APNs token received: ${token.substring(0, token.length.clamp(0, 8))}...',
        );
        _currentToken = token;
        unawaited(_registerPusher(token));
      case 'onRegistrationError':
        final error = call.arguments as String;
        debugPrint('[Lattice] APNs registration error: $error');
      case 'onRemoteMessage':
        final payload = Map<String, dynamic>.from(call.arguments as Map);
        unawaited(_processPushMessage(payload));
      case 'onNotificationTap':
        final roomId = call.arguments as String;
        debugPrint('[Lattice] APNs notification tapped for room $roomId');
        notificationService.navigateToRoom(roomId);
      case 'onNotificationReply':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final roomId = args['roomId'] as String;
        final text = args['text'] as String;
        debugPrint('[Lattice] APNs inline reply for room $roomId');
        unawaited(_handleInlineReply(roomId, text));
      case 'onNotificationMarkAsRead':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final roomId = args['roomId'] as String;
        final eventId = args['eventId'] as String?;
        debugPrint('[Lattice] APNs mark as read for room $roomId');
        unawaited(_handleMarkAsRead(roomId, eventId));
    }
  }

  // ── Registration ─────────────────────────────────────────────

  Future<void> register() async {
    if (!isNativeIOS) return;
    if (!preferencesService.apnsPushEnabled) return;
    if (!AppConfig.instance.apnsPushConfigured) return;

    try {
      await _channel.invokeMethod<void>('requestToken');
      debugPrint('[Lattice] APNs registration requested');
    } on PlatformException catch (e) {
      debugPrint('[Lattice] APNs registration failed: ${e.message}');
    }
  }

  Future<void> unregister() async {
    if (!isNativeIOS) return;
    try {
      await _unregisterPusher();
    } catch (e) {
      debugPrint('[Lattice] Failed to unregister APNs pusher: $e');
    }
    try {
      await _channel.invokeMethod<void>('unregister');
    } catch (e) {
      debugPrint('[Lattice] Failed to unregister from APNs: $e');
    }
    _currentToken = null;
    debugPrint('[Lattice] APNs unregistered');
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
            format: 'event_id_only',
          ),
          profileTag: client.deviceID,
        ),
        append: true,
      );
      debugPrint('[Lattice] APNs pusher registered with gateway $gatewayUrl');
    } catch (e) {
      debugPrint('[Lattice] Failed to register APNs pusher: $e');
    }
  }

  Future<void> _unregisterPusher() async {
    final token = _currentToken;
    if (token == null) return;

    final client = matrixService.client;
    await client.deletePusher(
      PusherId(appId: _appId, pushkey: token),
    );
    debugPrint('[Lattice] APNs pusher unregistered from homeserver');
  }

  // ── Push message processing ──────────────────────────────────

  Future<void> _processPushMessage(Map<String, dynamic> payload) async {
    if (_disposed) return;

    try {
      final notification =
          payload['notification'] as Map<String, dynamic>?;
      if (notification == null) return;

      final eventId = notification['event_id'] as String?;
      final roomId = notification['room_id'] as String?;
      if (roomId == null) return;

      final client = matrixService.client;
      final room = client.getRoomById(roomId);

      if (eventId == null) return;

      MatrixEvent matrixEvent;
      try {
        matrixEvent = await client.getOneRoomEvent(roomId, eventId);
      } catch (e) {
        debugPrint('[Lattice] Failed to fetch push event: $e');
        return;
      }

      if (matrixEvent.type == 'm.call.invite' ||
          matrixEvent.type == 'm.call.member') {
        _handleCallEvent(roomId, matrixEvent, room);
      }
    } catch (e) {
      debugPrint('[Lattice] APNs push message processing error: $e');
    }
  }

  void _handleCallEvent(String roomId, MatrixEvent event, Room? room) {
    final content = event.content;
    final callId = content['call_id'] as String?;
    final callerName = room?.getLocalizedDisplayname() ?? roomId;
    final isVideo =
        (content['offer'] as Map?)
            ?['sdp']
            ?.toString()
            .contains('m=video') ??
        false;

    callService.handlePushCallInvite(
      roomId: roomId,
      callId: callId,
      callerName: callerName,
      isVideo: isVideo,
    );
  }

  // ── Notification actions ─────────────────────────────────────

  Future<void> _handleInlineReply(String roomId, String text) async {
    if (_disposed || text.isEmpty) return;
    try {
      final room = matrixService.client.getRoomById(roomId);
      if (room == null) {
        debugPrint('[Lattice] Reply failed: room $roomId not found');
        return;
      }
      await room.sendTextEvent(text);
      debugPrint('[Lattice] Inline reply sent to room $roomId');
    } catch (e) {
      debugPrint('[Lattice] Failed to send inline reply: $e');
    }
  }

  Future<void> _handleMarkAsRead(String roomId, String? eventId) async {
    if (_disposed) return;
    try {
      final room = matrixService.client.getRoomById(roomId);
      if (room == null) {
        debugPrint('[Lattice] Mark as read failed: room $roomId not found');
        return;
      }
      final targetEventId = eventId ?? room.lastEvent?.eventId;
      if (targetEventId == null) return;
      await room.setReadMarker(targetEventId, mRead: targetEventId);
      debugPrint('[Lattice] Marked room $roomId as read');
    } catch (e) {
      debugPrint('[Lattice] Failed to mark as read: $e');
    }
  }

  // ── Badge ────────────────────────────────────────────────────

  static Future<void> clearBadge() async {
    if (!isNativeIOS) return;
    try {
      await _channel.invokeMethod<void>('clearBadge');
    } catch (e) {
      debugPrint('[Lattice] Failed to clear badge: $e');
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

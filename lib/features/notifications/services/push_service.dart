import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/notification_filter.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/notifications/services/notification_service.dart';
import 'package:matrix/matrix.dart';
import 'package:unifiedpush/unifiedpush.dart';

class PushService {
  PushService({
    required this.matrixService,
    required this.preferencesService,
    required this.notificationService,
    required this.callService,
  });

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final NotificationService notificationService;
  final CallService callService;

  String? _currentEndpoint;
  bool _initialized = false;
  bool _disposed = false;

  static const String _appId = NotificationChannel.appId;
  static const String _defaultGatewayUrl =
      NotificationChannel.defaultGatewayUrl;

  // ── Initialization ───────────────────────────────────────────

  Future<void> init() async {
    if (!isNativeAndroid) return;
    if (_initialized) return;
    _initialized = true;

    await UnifiedPush.initialize(
      onNewEndpoint: _onNewEndpoint,
      onRegistrationFailed: _onRegistrationFailed,
      onUnregistered: _onUnregistered,
      onMessage: _onMessage,
    );

    final savedDistributor = preferencesService.pushDistributor;
    if (savedDistributor != null) {
      await UnifiedPush.saveDistributor(savedDistributor);
    }

    debugPrint('[Kohera] PushService initialized');
  }

  // ── Registration ─────────────────────────────────────────────

  Future<void> register() async {
    if (!isNativeAndroid) return;
    if (!preferencesService.pushEnabled) return;

    final hasDistributor = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
    if (!hasDistributor) {
      debugPrint('[Kohera] No UnifiedPush distributor available');
      return;
    }

    await UnifiedPush.register();
    debugPrint('[Kohera] UnifiedPush registration requested');
  }

  Future<void> unregister() async {
    if (!isNativeAndroid) return;
    try {
      await _unregisterPusher();
    } catch (e) {
      debugPrint('[Kohera] Failed to unregister pusher: $e');
    }
    try {
      await UnifiedPush.unregister();
    } catch (e) {
      debugPrint('[Kohera] Failed to unregister from distributor: $e');
    }
    _currentEndpoint = null;
    debugPrint('[Kohera] UnifiedPush unregistered');
  }

  // ── UnifiedPush callbacks ────────────────────────────────────

  void _onNewEndpoint(PushEndpoint endpoint, String instance) {
    final url = endpoint.url;
    debugPrint('[Kohera] New push endpoint: $url');
    _currentEndpoint = url;
    unawaited(_registerPusher(url));
  }

  void _onRegistrationFailed(FailedReason reason, String instance) {
    debugPrint('[Kohera] Push registration failed: $reason');
  }

  void _onUnregistered(String instance) {
    debugPrint('[Kohera] Push unregistered by distributor');
    _currentEndpoint = null;
  }

  void _onMessage(PushMessage message, String instance) {
    unawaited(_processPushMessage(message.content));
  }

  // ── Pusher registration ──────────────────────────────────────

  Future<void> _registerPusher(String endpoint) async {
    if (_disposed) return;
    final client = matrixService.client;
    if (client.userID == null) return;

    final gatewayUrl = _gatewayUrl;

    await client.postPusher(
      Pusher(
        appId: _appId,
        pushkey: endpoint,
        appDisplayName: NotificationChannel.appName,
        deviceDisplayName:
            client.deviceName ?? NotificationChannel.defaultDeviceName,
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
    debugPrint('[Kohera] Pusher registered with gateway $gatewayUrl');
  }

  Future<void> _unregisterPusher() async {
    final endpoint = _currentEndpoint;
    if (endpoint == null) return;

    final client = matrixService.client;
    await client.deletePusher(
      PusherId(appId: _appId, pushkey: endpoint),
    );
    debugPrint('[Kohera] Pusher unregistered from homeserver');
  }

  // ── Push message processing ──────────────────────────────────

  Future<void> _processPushMessage(Uint8List rawContent) async {
    if (_disposed) return;
    if (!preferencesService.osNotificationsEnabled) return;
    if (preferencesService.notificationLevel == NotificationLevel.off) return;

    try {
      final payload =
          json.decode(utf8.decode(rawContent)) as Map<String, dynamic>;
      final notification =
          payload['notification'] as Map<String, dynamic>?;
      if (notification == null) return;

      final eventId = notification['event_id'] as String?;
      final roomId = notification['room_id'] as String?;
      if (roomId == null) return;

      final client = matrixService.client;
      final room = client.getRoomById(roomId);

      if (room?.pushRuleState == PushRuleState.dontNotify) return;

      if (eventId == null) {
        await notificationService.showPushNotification(
          roomId: roomId,
          title: room?.getLocalizedDisplayname() ??
              NotificationText.newMessageTitle,
          body: NotificationText.newMessageBody,
        );
        return;
      }

      MatrixEvent matrixEvent;
      try {
        matrixEvent = await client.getOneRoomEvent(roomId, eventId);
      } catch (e) {
        debugPrint('[Kohera] Failed to fetch push event: $e');
        await notificationService.showPushNotification(
          roomId: roomId,
          title: room?.getLocalizedDisplayname() ??
              NotificationText.newMessageTitle,
          body: NotificationText.newMessageBody,
        );
        return;
      }

      if (matrixEvent.type == 'org.matrix.msc3401.call.member') {
        _handleCallEvent(roomId, matrixEvent, room);
        return;
      }

      if (room == null) {
        await notificationService.showPushNotification(
          roomId: roomId,
          title: NotificationText.newMessageTitle,
          body: NotificationText.newMessageBody,
        );
        return;
      }

      await _handleMessageEvent(room, matrixEvent);
    } catch (e) {
      debugPrint('[Kohera] Push message processing error: $e');
    }
  }

  Future<void> _handleMessageEvent(Room room, MatrixEvent matrixEvent) async {
    final client = matrixService.client;
    if (matrixEvent.senderId == client.userID) return;

    final event = Event.fromMatrixEvent(matrixEvent, room);
    String body;

    if (matrixEvent.type == EventTypes.Encrypted) {
      body = await _tryDecrypt(room, event);
    } else {
      body = event.body;
    }

    if (!shouldNotifyForEvent(
      eventBody: body,
      senderId: matrixEvent.senderId,
      ownUserId: client.userID,
      room: room,
      prefs: preferencesService,
    )) {
      return;
    }

    final sender =
        room.unsafeGetUserFromMemoryOrFallback(matrixEvent.senderId);

    await notificationService.showPushNotification(
      roomId: room.id,
      title: room.getLocalizedDisplayname(),
      senderName: sender.calcDisplayname(),
      body: body,
    );
  }

  void _handleCallEvent(String roomId, MatrixEvent event, Room? room) {
    final content = event.content;
    if (content.isEmpty) return;
    final callId = content['call_id'] as String? ?? '';
    final callerName = room?.getLocalizedDisplayname() ?? roomId;
    final isVideo = content[kIoKoheraIsVideo] == true;

    callService.handlePushCallInvite(
      roomId: roomId,
      callId: callId,
      callerName: callerName,
      isVideo: isVideo,
    );
  }

  // ── Decryption ───────────────────────────────────────────────

  Future<String> _tryDecrypt(Room room, Event event) async {
    try {
      final decrypted = await room.client.encryption
          ?.decryptRoomEvent(event)
          .timeout(const Duration(seconds: 3));
      return decrypted?.body ?? NotificationText.encryptedMessage;
    } catch (e) {
      debugPrint('[Kohera] Push decryption failed: $e');
      return NotificationText.encryptedMessage;
    }
  }

  // ── Gateway resolution ───────────────────────────────────────

  String get _gatewayUrl => _defaultGatewayUrl;

  // ── Distributor management ───────────────────────────────────

  Future<List<String>> getDistributors() => UnifiedPush.getDistributors();

  Future<void> selectDistributor(String distributor) async {
    await UnifiedPush.saveDistributor(distributor);
    await preferencesService.setPushDistributor(distributor);
    await unregister();
    await register();
  }

  // ── Lifecycle ────────────────────────────────────────────────

  void dispose() {
    _disposed = true;
    _initialized = false;
  }
}

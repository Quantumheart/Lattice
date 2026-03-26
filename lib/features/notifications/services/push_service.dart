import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/notifications/services/notification_service.dart';
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

  static const _appId = 'io.github.quantumheart.lattice';
  static const _defaultGatewayUrl =
      'https://matrix.gateway.unifiedpush.org/_matrix/push/v1/notify';

  // ── Initialization ───────────────────────────────────────────

  Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
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

    debugPrint('[Lattice] PushService initialized');
  }

  // ── Registration ─────────────────────────────────────────────

  Future<void> register() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (!preferencesService.pushEnabled) return;

    final hasDistributor = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
    if (!hasDistributor) {
      debugPrint('[Lattice] No UnifiedPush distributor available');
      return;
    }

    await UnifiedPush.register();
    debugPrint('[Lattice] UnifiedPush registration requested');
  }

  Future<void> unregister() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _unregisterPusher();
    } catch (e) {
      debugPrint('[Lattice] Failed to unregister pusher: $e');
    }
    try {
      await UnifiedPush.unregister();
    } catch (e) {
      debugPrint('[Lattice] Failed to unregister from distributor: $e');
    }
    _currentEndpoint = null;
    debugPrint('[Lattice] UnifiedPush unregistered');
  }

  // ── UnifiedPush callbacks ────────────────────────────────────

  void _onNewEndpoint(PushEndpoint endpoint, String instance) {
    final url = endpoint.url;
    debugPrint('[Lattice] New push endpoint: $url');
    _currentEndpoint = url;
    unawaited(_registerPusher(url));
  }

  void _onRegistrationFailed(FailedReason reason, String instance) {
    debugPrint('[Lattice] Push registration failed: $reason');
  }

  void _onUnregistered(String instance) {
    debugPrint('[Lattice] Push unregistered by distributor');
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
        appDisplayName: 'Lattice',
        deviceDisplayName: client.deviceName ?? 'Android',
        kind: 'http',
        lang: 'en',
        data: PusherData(
          url: Uri.parse(gatewayUrl),
          format: 'event_id_only',
        ),
        profileTag: client.deviceID,
      ),
      append: true,
    );
    debugPrint('[Lattice] Pusher registered with gateway $gatewayUrl');
  }

  Future<void> _unregisterPusher() async {
    final endpoint = _currentEndpoint;
    if (endpoint == null) return;

    final client = matrixService.client;
    await client.deletePusher(
      PusherId(appId: _appId, pushkey: endpoint),
    );
    debugPrint('[Lattice] Pusher unregistered from homeserver');
  }

  // ── Push message processing ──────────────────────────────────

  Future<void> _processPushMessage(Uint8List rawContent) async {
    if (_disposed) return;
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

      if (eventId == null) {
        await notificationService.showPushNotification(
          roomId: roomId,
          title: room?.getLocalizedDisplayname() ?? 'New message',
          body: 'You have a new message',
        );
        return;
      }

      MatrixEvent matrixEvent;
      try {
        matrixEvent = await client.getOneRoomEvent(roomId, eventId);
      } catch (e) {
        debugPrint('[Lattice] Failed to fetch push event: $e');
        await notificationService.showPushNotification(
          roomId: roomId,
          title: room?.getLocalizedDisplayname() ?? 'New message',
          body: 'You have a new message',
        );
        return;
      }

      if (matrixEvent.type == 'm.call.invite' ||
          matrixEvent.type == 'm.call.member') {
        _handleCallEvent(roomId, matrixEvent, room);
        return;
      }

      if (room == null) {
        await notificationService.showPushNotification(
          roomId: roomId,
          title: 'New message',
          body: 'You have a new message',
        );
        return;
      }

      await _handleMessageEvent(room, matrixEvent);
    } catch (e) {
      debugPrint('[Lattice] Push message processing error: $e');
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

  // ── Decryption ───────────────────────────────────────────────

  Future<String> _tryDecrypt(Room room, Event event) async {
    try {
      final decrypted = await room.client.encryption
          ?.decryptRoomEvent(event)
          .timeout(const Duration(seconds: 3));
      return decrypted?.body ?? 'Encrypted message';
    } catch (e) {
      debugPrint('[Lattice] Push decryption failed: $e');
      return 'Encrypted message';
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

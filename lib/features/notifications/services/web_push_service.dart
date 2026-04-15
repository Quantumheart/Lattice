import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:matrix/matrix.dart';
import 'package:web/web.dart' as web;

// ── JS interop helpers ────────────────────────────────────────

@JS('Object')
external JSObject _jsObject();

@JS('JSON.stringify')
external JSString _jsonStringify(JSObject obj);

JSObject _createSubscribeOptions({
  required bool userVisibleOnly,
  required JSUint8Array applicationServerKey,
}) {
  final obj = _jsObject();
  obj.setProperty('userVisibleOnly'.toJS, userVisibleOnly.toJS);
  obj.setProperty('applicationServerKey'.toJS, applicationServerKey);
  return obj;
}

// ── WebPushService ────────────────────────────────────────────

class WebPushService {
  WebPushService({
    required this.matrixService,
    required this.preferencesService,
    this.router,
  });

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final GoRouter? router;

  bool _disposed = false;
  web.EventListener? _messageListener;

  static const String _appId = NotificationChannel.webPushAppId;

  // ── Registration ─────────────────────────────────────────────

  Future<void> register() async {
    final config = AppConfig.instance;
    if (!config.webPushConfigured) {
      debugPrint('[Kohera] Web push not configured — skipping registration');
      return;
    }
    final vapidPublicKey = config.vapidPublicKey!;
    final gatewayUrl = config.webPushGatewayUrl!;
    if (_disposed) return;

    try {
      if (web.Notification.permission != 'granted') {
        debugPrint('[Kohera] Notification permission not granted');
        return;
      }

      final registration = await _getRegistration();
      if (registration == null) {
        debugPrint('[Kohera] No service worker registration found');
        return;
      }

      final applicationServerKey = _urlBase64ToUint8Array(vapidPublicKey);
      final options = _createSubscribeOptions(
        userVisibleOnly: true,
        applicationServerKey: applicationServerKey,
      );

      final regObj = registration as JSObject;
      final pushManager =
          regObj.getProperty<JSObject>('pushManager'.toJS);
      final subscriptionPromise =
          pushManager.callMethod<JSPromise<JSObject?>>('subscribe'.toJS, options);
      final subscription = await subscriptionPromise.toDart;

      if (subscription == null) {
        debugPrint('[Kohera] Web push subscription failed');
        return;
      }

      final pushkey = _jsonStringify(subscription).toDart;

      await _registerPusher(pushkey, gatewayUrl);
      debugPrint('[Kohera] Web push registered');
    } catch (e) {
      debugPrint('[Kohera] Web push registration error: $e');
    }
  }

  Future<void> unregister() async {
    try {
      final registration = await _getRegistration();
      if (registration == null) return;

      final regObj = registration as JSObject;
      final pushManager =
          regObj.getProperty<JSObject>('pushManager'.toJS);
      final subPromise =
          pushManager.callMethod<JSPromise<JSObject?>>('getSubscription'.toJS);
      final subscription = await subPromise.toDart;
      if (subscription == null) return;

      final pushkey = _jsonStringify(subscription).toDart;

      await _unregisterPusher(pushkey);

      final unsubPromise =
          subscription.callMethod<JSPromise<JSBoolean>>('unsubscribe'.toJS);
      await unsubPromise.toDart;
      debugPrint('[Kohera] Web push unregistered');
    } catch (e) {
      debugPrint('[Kohera] Web push unregister error: $e');
    }
  }

  // ── Pusher registration ──────────────────────────────────────

  Future<void> _registerPusher(String pushkey, String gatewayUrl) async {
    if (_disposed) return;
    final client = matrixService.client;
    if (client.userID == null) return;

    await client.postPusher(
      Pusher(
        appId: _appId,
        pushkey: pushkey,
        appDisplayName: NotificationChannel.appName,
        deviceDisplayName:
            client.deviceName ?? NotificationChannel.webDefaultDeviceName,
        kind: 'http',
        lang: NotificationChannel.defaultLang,
        data: PusherData(
          url: Uri.parse(gatewayUrl),
        ),
        profileTag: client.deviceID,
      ),
      append: true,
    );
    debugPrint('[Kohera] Web pusher registered with gateway $gatewayUrl');
  }

  Future<void> _unregisterPusher(String pushkey) async {
    final client = matrixService.client;
    await client.deletePusher(
      PusherId(appId: _appId, pushkey: pushkey),
    );
    debugPrint('[Kohera] Web pusher unregistered from homeserver');
  }

  // ── Subscription change listener ─────────────────────────────

  void listenForSubscriptionChanges() {
    final config = AppConfig.instance;
    if (!config.webPushConfigured) return;
    final gatewayUrl = config.webPushGatewayUrl!;

    _messageListener = (web.Event event) {
      try {
        final msgEvent = event as web.MessageEvent;
        final data = msgEvent.data;
        if (data == null) return;
        final obj = data as JSObject;
        final type = obj.getProperty<JSString>('type'.toJS).toDart;

        switch (type) {
          case 'pushsubscriptionchange':
            final newSubJs = obj.getProperty<JSObject>('newSubscription'.toJS);
            final newPushkey = _jsonStringify(newSubJs).toDart;
            unawaited(_registerPusher(newPushkey, gatewayUrl));
            debugPrint('[Kohera] Web push subscription renewed');

          case 'pushsubscriptionfailed':
            final error = obj.getProperty<JSString>('error'.toJS).toDart;
            debugPrint('[Kohera] Web push subscription renewal failed: $error');
            unawaited(register());

          case 'notification_click':
            final roomId = obj.getProperty<JSString>('roomId'.toJS).toDart;
            if (roomId.isNotEmpty) {
              if (router != null) {
                router!.goNamed(Routes.room, pathParameters: {'roomId': roomId});
              } else {
                matrixService.selection.selectRoom(roomId);
              }
              debugPrint('[Kohera] Web push notification tapped, navigating to room $roomId');
            }

          case 'mark_read':
            final roomId = obj.getProperty<JSString>('roomId'.toJS).toDart;
            if (roomId.isNotEmpty) {
              final room = matrixService.client.getRoomById(roomId);
              final lastEventId = room?.lastEvent?.eventId;
              if (room != null && lastEventId != null) {
                unawaited(
                  room.setReadMarker(lastEventId, mRead: lastEventId).catchError((Object e) {
                    debugPrint('[Kohera] Failed to mark room as read: $e');
                  }),
                );
              }
              debugPrint('[Kohera] Web push mark_read for room $roomId');
            }
        }
      } catch (e) {
        debugPrint('[Kohera] Error handling service worker message: $e');
      }
    }.toJS;

    web.window.navigator.serviceWorker
        .addEventListener('message', _messageListener);
  }

  // ── Permissions ─────────────────────────────────────────────

  static Future<bool> requestPermission() async {
    final result = (await web.Notification.requestPermission().toDart).toDart;
    return result == 'granted';
  }

  // ── Helpers ──────────────────────────────────────────────────

  Future<web.ServiceWorkerRegistration?> _getRegistration() async {
    final container = web.window.navigator.serviceWorker;
    final reg = await container.ready.toDart;
    return reg;
  }

  static JSUint8Array _urlBase64ToUint8Array(String base64String) {
    final padding = '=' * ((4 - base64String.length % 4) % 4);
    final b64 = (base64String + padding)
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    final rawData = base64Decode(b64);
    return rawData.toJS;
  }

  // ── Lifecycle ────────────────────────────────────────────────

  void dispose() {
    _disposed = true;
    final listener = _messageListener;
    if (listener != null) {
      web.window.navigator.serviceWorker
          .removeEventListener('message', listener);
      _messageListener = null;
    }
  }
}

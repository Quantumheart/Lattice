import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/app_config.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/notifications/models/notification_constants.dart';
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
  });

  final MatrixService matrixService;
  final PreferencesService preferencesService;

  bool _disposed = false;
  web.EventListener? _messageListener;

  static const String _appId = NotificationChannel.webPushAppId;

  // ── Registration ─────────────────────────────────────────────

  Future<void> register() async {
    final config = AppConfig.instance;
    if (!config.webPushConfigured) {
      debugPrint('[Lattice] Web push not configured — skipping registration');
      return;
    }
    final vapidPublicKey = config.vapidPublicKey!;
    final gatewayUrl = config.webPushGatewayUrl!;
    if (_disposed) return;

    try {
      if (web.Notification.permission != 'granted') {
        debugPrint('[Lattice] Notification permission not granted');
        return;
      }

      final registration = await _getRegistration();
      if (registration == null) {
        debugPrint('[Lattice] No service worker registration found');
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
        debugPrint('[Lattice] Web push subscription failed');
        return;
      }

      final pushkey = _jsonStringify(subscription).toDart;

      await _registerPusher(pushkey, gatewayUrl);
      debugPrint('[Lattice] Web push registered');
    } catch (e) {
      debugPrint('[Lattice] Web push registration error: $e');
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
      debugPrint('[Lattice] Web push unregistered');
    } catch (e) {
      debugPrint('[Lattice] Web push unregister error: $e');
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
          format: 'event_id_only',
        ),
        profileTag: client.deviceID,
      ),
      append: true,
    );
    debugPrint('[Lattice] Web pusher registered with gateway $gatewayUrl');
  }

  Future<void> _unregisterPusher(String pushkey) async {
    final client = matrixService.client;
    await client.deletePusher(
      PusherId(appId: _appId, pushkey: pushkey),
    );
    debugPrint('[Lattice] Web pusher unregistered from homeserver');
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
        if (type != 'pushsubscriptionchange') return;

        final newSubJs =
            obj.getProperty<JSObject>('newSubscription'.toJS);
        final newPushkey = _jsonStringify(newSubJs).toDart;
        unawaited(_registerPusher(newPushkey, gatewayUrl));
        debugPrint('[Lattice] Web push subscription renewed');
      } catch (e) {
        debugPrint('[Lattice] Error handling service worker message: $e');
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

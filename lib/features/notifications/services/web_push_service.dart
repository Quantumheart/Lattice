import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/notifications/models/notification_constants.dart';
import 'package:matrix/matrix.dart';
import 'package:web/web.dart' as web;

// ── JS interop bindings ───────────────────────────────────────

extension type _PushSubscriptionOptions._(JSObject _) implements JSObject {
  external factory _PushSubscriptionOptions({
    bool userVisibleOnly,
    JSObject? applicationServerKey,
  });
}

extension type _PushSubscription._(JSObject _) implements JSObject {
  external String get endpoint;
  external JSArrayBuffer? getKey(String name);
  external JSPromise<JSBoolean> unsubscribe();
}

extension type _PushManager._(JSObject _) implements JSObject {
  external JSPromise<_PushSubscription?> subscribe(
    _PushSubscriptionOptions options,
  );
  external JSPromise<_PushSubscription?> getSubscription();
}

extension type _ServiceWorkerRegistration._(JSObject _) implements JSObject {
  external _PushManager get pushManager;
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

  static const String _appId = NotificationChannel.webPushAppId;
  static const String _gatewayUrl = NotificationChannel.webPushGatewayUrl;

  // ── Registration ─────────────────────────────────────────────

  Future<void> register(String vapidPublicKey) async {
    if (_disposed) return;

    try {
      final registration = await _getRegistration();
      if (registration == null) {
        debugPrint('[Lattice] No service worker registration found');
        return;
      }

      final applicationServerKey = _urlBase64ToUint8Array(vapidPublicKey);

      final subscription = await registration.pushManager
          .subscribe(
            _PushSubscriptionOptions(
              userVisibleOnly: true,
              applicationServerKey: applicationServerKey,
            ),
          )
          .toDart;

      if (subscription == null) {
        debugPrint('[Lattice] Web push subscription failed');
        return;
      }

      await _registerPusher(subscription);
      debugPrint('[Lattice] Web push registered: ${subscription.endpoint}');
    } catch (e) {
      debugPrint('[Lattice] Web push registration error: $e');
    }
  }

  Future<void> unregister() async {
    try {
      final registration = await _getRegistration();
      if (registration == null) return;

      final subscription =
          await registration.pushManager.getSubscription().toDart;
      if (subscription == null) return;

      await _unregisterPusher(subscription.endpoint);
      await subscription.unsubscribe().toDart;
      debugPrint('[Lattice] Web push unregistered');
    } catch (e) {
      debugPrint('[Lattice] Web push unregister error: $e');
    }
  }

  // ── Pusher registration ──────────────────────────────────────

  Future<void> _registerPusher(_PushSubscription subscription) async {
    if (_disposed) return;
    final client = matrixService.client;
    if (client.userID == null) return;

    await client.postPusher(
      Pusher(
        appId: _appId,
        pushkey: subscription.endpoint,
        appDisplayName: NotificationChannel.appName,
        deviceDisplayName:
            client.deviceName ?? NotificationChannel.webDefaultDeviceName,
        kind: 'http',
        lang: NotificationChannel.defaultLang,
        data: PusherData(
          url: Uri.parse(_gatewayUrl),
          format: 'event_id_only',
        ),
        profileTag: client.deviceID,
      ),
      append: true,
    );
    debugPrint('[Lattice] Web pusher registered with gateway $_gatewayUrl');
  }

  Future<void> _unregisterPusher(String endpoint) async {
    final client = matrixService.client;
    await client.deletePusher(
      PusherId(appId: _appId, pushkey: endpoint),
    );
    debugPrint('[Lattice] Web pusher unregistered from homeserver');
  }

  // ── Helpers ──────────────────────────────────────────────────

  Future<_ServiceWorkerRegistration?> _getRegistration() async {
    final container = web.window.navigator.serviceWorker;
    final reg = await container.ready.toDart;
    return reg as _ServiceWorkerRegistration?;
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
  }
}

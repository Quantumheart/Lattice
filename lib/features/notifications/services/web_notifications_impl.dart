import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

final Map<String, web.Notification> _activeFallback = {};

web.ServiceWorker? get _swController =>
    web.window.navigator.serviceWorker.controller;

// ── Show notification ────────────────────────────────────────

void showWebNotification({
  required String title,
  required String body,
  String? icon,
  String? tag,
  String? roomId,
  bool silent = false,
  bool renotify = true,
  int unreadCount = 0,
}) {
  if (web.Notification.permission != 'granted') return;

  if (!silent) unawaited(_playNotificationSound());

  final sw = _swController;
  if (sw != null) {
    final msg = JSObject();
    msg.setProperty('type'.toJS, 'show_notification'.toJS);
    msg.setProperty('title'.toJS, title.toJS);
    msg.setProperty('body'.toJS, body.toJS);
    msg.setProperty('tag'.toJS, (tag ?? '').toJS);
    msg.setProperty('roomId'.toJS, (roomId ?? tag ?? '').toJS);
    // SW notification is always silent — sound is played client-side above.
    msg.setProperty('silent'.toJS, true.toJS);
    msg.setProperty('renotify'.toJS, renotify.toJS);
    msg.setProperty('unreadCount'.toJS, unreadCount.toJS);
    if (icon != null) msg.setProperty('icon'.toJS, icon.toJS);
    sw.postMessage(msg);
    return;
  }

  final options = web.NotificationOptions(body: body);
  if (tag != null) options.tag = tag;
  if (icon != null) options.icon = icon;

  final notification = web.Notification(title, options);

  if (tag != null) {
    _activeFallback[tag]?.close();
    _activeFallback[tag] = notification;
  }
}

// ── Close notifications ──────────────────────────────────────

void closeWebNotification(String tag) {
  final sw = _swController;
  if (sw != null) {
    final msg = JSObject();
    msg.setProperty('type'.toJS, 'close_notification'.toJS);
    msg.setProperty('tag'.toJS, tag.toJS);
    sw.postMessage(msg);
    return;
  }
  _activeFallback.remove(tag)?.close();
}

void closeAllWebNotifications() {
  final sw = _swController;
  if (sw != null) {
    final msg = JSObject();
    msg.setProperty('type'.toJS, 'close_all_notifications'.toJS);
    sw.postMessage(msg);
    return;
  }
  for (final n in _activeFallback.values) {
    n.close();
  }
  _activeFallback.clear();
}

// ── App badge ────────────────────────────────────────────────

void clearWebAppBadge() {
  final sw = _swController;
  if (sw == null) return;
  final msg = JSObject();
  msg.setProperty('type'.toJS, 'clear_badge'.toJS);
  sw.postMessage(msg);
}

// ── Avatar resolution ────────────────────────────────────────

Future<String?> resolveWebAvatarUrl(
  String url,
  Map<String, String>? headers,
) async {
  try {
    final init = web.RequestInit(method: 'GET');
    if (headers != null && headers.isNotEmpty) {
      final h = web.Headers();
      headers.forEach(h.set);
      init.headers = h;
    }
    final response = await web.window.fetch(url.toJS, init).toDart;
    if (!response.ok) return null;
    final blob = await response.blob().toDart;
    final reader = web.FileReader();
    final completer = Completer<String?>();
    reader.onload = (web.Event _) {
      completer.complete((reader.result as JSString?)?.toDart);
    }.toJS;
    reader.onerror = (web.Event _) {
      completer.complete(null);
    }.toJS;
    reader.readAsDataURL(blob);
    return await completer.future;
  } catch (_) {
    return null;
  }
}

// ── Sound playback ───────────────────────────────────────────

Future<void> _playNotificationSound() async {
  try {
    final audio = web.HTMLAudioElement()..src = 'audio/notification.mp3';
    await audio.play().toDart;
  } catch (e) {
    debugPrint('[Lattice] Failed to play notification sound: $e');
  }
}

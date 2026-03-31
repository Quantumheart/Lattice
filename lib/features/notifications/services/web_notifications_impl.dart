import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

final Map<String, web.Notification> _active = {};

Future<void> requestWebNotificationPermission() async {
  try {
    await web.Notification.requestPermission().toDart;
    debugPrint('[Lattice] Web notification permission: ${web.Notification.permission}');
  } catch (e) {
    debugPrint('[Lattice] Failed to request notification permission: $e');
  }
}

void showWebNotification({
  required String title,
  required String body,
  String? icon,
  String? tag,
  void Function()? onClick,
}) {
  if (web.Notification.permission != 'granted') return;

  final options = web.NotificationOptions(body: body);
  if (tag != null) options.tag = tag;
  if (icon != null) options.icon = icon;

  final notification = web.Notification(title, options);

  if (onClick != null) {
    notification.onclick = (web.Event event) {
      event.preventDefault();
      web.window.focus();
      onClick();
      notification.close();
    }.toJS;
  }

  if (tag != null) {
    _active[tag]?.close();
    _active[tag] = notification;
  }
}

void closeWebNotification(String tag) {
  _active.remove(tag)?.close();
}

void closeAllWebNotifications() {
  for (final n in _active.values) {
    n.close();
  }
  _active.clear();
}

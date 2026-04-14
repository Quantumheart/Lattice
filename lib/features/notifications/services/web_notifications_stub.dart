void showWebNotification({
  required String title,
  required String body,
  String? icon,
  String? tag,
  String? roomId,
  bool silent = false,
  bool renotify = true,
  int unreadCount = 0,
}) {}

void closeWebNotification(String tag) {}

void closeAllWebNotifications() {}

void clearWebAppBadge() {}

Future<String?> resolveWebAvatarUrl(
  String url,
  Map<String, String>? headers,
) async =>
    null;

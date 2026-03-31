Future<void> requestWebNotificationPermission() async {}

void showWebNotification({
  required String title,
  required String body,
  String? icon,
  String? tag,
  void Function()? onClick,
}) {}

void closeWebNotification(String tag) {}

void closeAllWebNotifications() {}

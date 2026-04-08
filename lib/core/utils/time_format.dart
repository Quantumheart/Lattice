String formatMessageTime(DateTime ts) {
  final h = ts.hour.toString().padLeft(2, '0');
  final m = ts.minute.toString().padLeft(2, '0');
  final time = '$h:$m';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDate = DateTime(ts.year, ts.month, ts.day);
  final diff = today.difference(msgDate).inDays;

  if (diff == 0) return time;
  if (diff == 1) return 'Yesterday $time';

  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  if (diff < 7) return '${weekdays[ts.weekday - 1]} $time';
  if (ts.year == now.year) return '${months[ts.month - 1]} ${ts.day}, $time';
  return '${months[ts.month - 1]} ${ts.day}, ${ts.year}, $time';
}

String formatRelativeTimestamp(DateTime ts) {
  final now = DateTime.now();
  final diff = now.difference(ts);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 24) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}';
}

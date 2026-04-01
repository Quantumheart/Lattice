bool isNetworkError(Object e) {
  final msg = e.toString().toLowerCase();
  return msg.contains('xmlhttprequest') ||
      msg.contains('failed to fetch') ||
      msg.contains('networkerror') ||
      msg.contains('network error');
}

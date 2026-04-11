import 'dart:js_interop';

import 'package:web/web.dart' as web;

class _FocusListenerHandle {
  _FocusListenerHandle(this.onFocus, this.onBlur);
  final web.EventListener onFocus;
  final web.EventListener onBlur;
}

Object? registerWindowFocusListeners({
  required void Function() onFocus,
  required void Function() onBlur,
}) {
  final handle = _FocusListenerHandle(
    (web.Event _) { onFocus(); }.toJS,
    (web.Event _) { onBlur(); }.toJS,
  );
  web.window.addEventListener('focus', handle.onFocus);
  web.window.addEventListener('blur', handle.onBlur);
  return handle;
}

void unregisterWindowFocusListeners(Object? handle) {
  if (handle is! _FocusListenerHandle) return;
  web.window.removeEventListener('focus', handle.onFocus);
  web.window.removeEventListener('blur', handle.onBlur);
}

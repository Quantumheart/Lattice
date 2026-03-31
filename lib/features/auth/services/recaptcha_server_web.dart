import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

String _escapeHtmlAttr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#x27;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

// ── RecaptchaServer (Web) ───────────────────────────────────────────────────

class RecaptchaServer {
  RecaptchaServer({required this.siteKey});

  final String siteKey;

  final Completer<String> _tokenCompleter = Completer<String>();
  Timer? _timeout;
  web.Window? _popup;
  JSFunction? _messageListener;

  Future<String> get tokenFuture => _tokenCompleter.future;

  static const _timeoutDuration = Duration(minutes: 5);

  Future<String> start() async {
    _timeout = Timer(_timeoutDuration, () {
      if (!_tokenCompleter.isCompleted) {
        debugPrint('[Lattice] RecaptchaServer timed out');
        _tokenCompleter.completeError(
          RecaptchaException('reCAPTCHA timed out. Please try again.'),
        );
        dispose();
      }
    });

    _messageListener = (web.Event event) {
      if (event.type != 'message') return;
      final data = (event as web.MessageEvent).data;
      if (data == null) return;

      final map = data.dartify();
      if (map is! Map) return;
      if (map['type'] != 'recaptcha-token') return;

      final token = map['token'] as String?;
      if (token != null && token.isNotEmpty && !_tokenCompleter.isCompleted) {
        debugPrint('[Lattice] reCAPTCHA token received via postMessage');
        _tokenCompleter.complete(token);
        _popup?.close();
        _popup = null;
      }
    }.toJS;
    web.window.addEventListener('message', _messageListener);

    final html = _buildHtmlPage();
    final blob = web.Blob(
      [html.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html'),
    );
    return web.URL.createObjectURL(blob);
  }

  Future<void> launch(Uri url) async {
    _popup = web.window.open(
      url.toString(),
      'lattice_recaptcha',
      'width=450,height=600,popup=yes',
    );
    if (_popup == null) {
      throw RecaptchaException(
        'Could not open popup. Please allow popups for this site.',
      );
    }
  }

  String _buildHtmlPage() => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Verify you are human</title>
  <script src="https://www.google.com/recaptcha/api.js" async defer></script>
  <style>
    body {
      font-family: sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      background: #f8f9fa;
    }
    h2 { margin-bottom: 24px; }
  </style>
</head>
<body>
  <div>
    <h2>Verify you are human</h2>
    <div class="g-recaptcha"
         data-sitekey="${_escapeHtmlAttr(siteKey)}"
         data-callback="onCaptchaComplete"></div>
  </div>
  <script>
    function onCaptchaComplete(token) {
      window.opener.postMessage({type: 'recaptcha-token', token: token}, '*');
      window.close();
    }
  </script>
</body>
</html>
''';

  void dispose() {
    _timeout?.cancel();
    _timeout = null;
    _popup?.close();
    _popup = null;
    if (_messageListener != null) {
      web.window.removeEventListener('message', _messageListener);
      _messageListener = null;
    }
    if (!_tokenCompleter.isCompleted) {
      _tokenCompleter.completeError(
        RecaptchaException('reCAPTCHA was cancelled.'),
      );
    }
  }
}

class RecaptchaException implements Exception {
  RecaptchaException(this.message);
  final String message;

  @override
  String toString() => message;
}

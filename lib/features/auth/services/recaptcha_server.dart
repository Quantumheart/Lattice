import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Escapes a string for safe use inside an HTML attribute value.
String _escapeHtmlAttr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#x27;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

// ── RecaptchaServer ─────────────────────────────────────────────────────────

/// Starts a temporary localhost HTTP server that serves a reCAPTCHA page and
/// captures the response token when the user completes the challenge.
///
/// Lifecycle:
///   1. Call [start] to bind and get the URL to open in the browser.
///   2. Await [tokenFuture] to receive the token.
///   3. Call [dispose] to shut down (safe to call multiple times).
class RecaptchaServer {
  RecaptchaServer({required this.siteKey});

  final String siteKey;

  HttpServer? _server;
  final Completer<String> _tokenCompleter = Completer<String>();
  Timer? _timeout;

  /// Completes with the reCAPTCHA response token on success,
  /// or errors with a [RecaptchaException] on failure or timeout.
  Future<String> get tokenFuture => _tokenCompleter.future;

  static const _timeoutDuration = Duration(minutes: 5);

  /// Binds to a random localhost port.
  /// Returns the URL to open in the system browser.
  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = _server!.port;
    debugPrint('[Lattice] RecaptchaServer listening on port $port');

    _timeout = Timer(_timeoutDuration, () {
      if (!_tokenCompleter.isCompleted) {
        debugPrint('[Lattice] RecaptchaServer timed out');
        _tokenCompleter.completeError(
          RecaptchaException('reCAPTCHA timed out. Please try again.'),
        );
        dispose();
      }
    });

    _serve();
    return 'http://127.0.0.1:$port/';
  }

  void _serve() {
    _server?.listen((HttpRequest request) async {
      try {
        if (request.method == 'GET' && request.uri.path == '/') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_buildHtmlPage())
            ..close();
          return;
        }

        if (request.method == 'POST' && request.uri.path == '/token') {
          final body = await request
              .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
          final params = Uri.splitQueryString(String.fromCharCodes(body));
          final token = params['g-recaptcha-response'];

          if (token != null && token.isNotEmpty) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(_buildSuccessPage())
              ..close();

            if (!_tokenCompleter.isCompleted) {
              _tokenCompleter.complete(token);
            }
            Future<void>.delayed(
              const Duration(seconds: 1),
              () => dispose(),
            );
          } else {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write('Missing token')
              ..close();
          }
          return;
        }

        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
      } catch (e) {
        debugPrint('[Lattice] RecaptchaServer request error: $e');
        try {
          request.response.close();
        } catch (_) {}
      }
    });
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
    <form id="captchaForm" method="POST" action="/token">
      <input type="hidden" id="tokenField" name="g-recaptcha-response" value="">
      <div class="g-recaptcha"
           data-sitekey="${_escapeHtmlAttr(siteKey)}"
           data-callback="onCaptchaComplete"></div>
    </form>
  </div>
  <script>
    function onCaptchaComplete(token) {
      document.getElementById('tokenField').value = token;
      document.getElementById('captchaForm').submit();
    }
  </script>
</body>
</html>
''';

  String _buildSuccessPage() => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Done</title>
  <style>
    body {
      font-family: sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      background: #f8f9fa;
    }
  </style>
</head>
<body>
  <div style="text-align: center">
    <h2>Verification complete</h2>
    <p>You can close this tab and return to Lattice.</p>
  </div>
</body>
</html>
''';

  void dispose() {
    _timeout?.cancel();
    _timeout = null;
    _server?.close(force: true).then((_) {
      debugPrint('[Lattice] RecaptchaServer shut down');
    });
    _server = null;
    if (!_tokenCompleter.isCompleted) {
      _tokenCompleter.completeError(
        RecaptchaException('reCAPTCHA was cancelled.'),
      );
    }
  }
}

/// Exception thrown when the reCAPTCHA flow fails or is cancelled.
class RecaptchaException implements Exception {
  RecaptchaException(this.message);
  final String message;

  @override
  String toString() => message;
}

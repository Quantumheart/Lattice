import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

String _escapeHtmlAttr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#x27;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

// ── RecaptchaServer ─────────────────────────────────────────────────────────

class RecaptchaServer {
  RecaptchaServer({required this.siteKey});

  final String siteKey;

  HttpServer? _server;
  final Completer<String> _tokenCompleter = Completer<String>();
  Timer? _timeout;

  Future<String> get tokenFuture => _tokenCompleter.future;

  static const _timeoutDuration = Duration(minutes: 5);

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = _server!.port;
    debugPrint('[Kohera] RecaptchaServer listening on port $port');

    _timeout = Timer(_timeoutDuration, () {
      if (!_tokenCompleter.isCompleted) {
        debugPrint('[Kohera] RecaptchaServer timed out');
        _tokenCompleter.completeError(
          RecaptchaException('reCAPTCHA timed out. Please try again.'),
        );
        dispose();
      }
    });

    _serve();
    return 'http://127.0.0.1:$port/';
  }

  Future<void> launch(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw RecaptchaException('Could not open browser');
    }
  }

  void _serve() {
    _server?.listen((request) async {
      try {
        if (request.method == 'GET' && request.uri.path == '/') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_buildHtmlPage());
          unawaited(request.response.close());
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
              ..write(_buildSuccessPage());
            unawaited(request.response.close());

            if (!_tokenCompleter.isCompleted) {
              _tokenCompleter.complete(token);
            }
            Future<void>.delayed(
              const Duration(seconds: 1),
              dispose,
            );
          } else {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write('Missing token');
            unawaited(request.response.close());
          }
          return;
        }

        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        unawaited(request.response.close());
      } catch (e) {
        debugPrint('[Kohera] RecaptchaServer request error: $e');
        try {
          unawaited(request.response.close());
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
    <p>You can close this tab and return to Kohera.</p>
  </div>
</body>
</html>
''';

  void dispose() {
    _timeout?.cancel();
    _timeout = null;
    unawaited(_server?.close(force: true).then((_) {
      debugPrint('[Kohera] RecaptchaServer shut down');
    }),);
    _server = null;
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

// ── SsoCallbackServer ───────────────────────────────────────────────────────

class SsoCallbackServer {
  SsoCallbackServer({this.homeserver});

  final String? homeserver;
  HttpServer? _server;
  final Completer<String> _tokenCompleter = Completer<String>();
  Timer? _timeout;

  Future<String> get tokenFuture => _tokenCompleter.future;

  static const _timeoutDuration = Duration(minutes: 5);

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = _server!.port;
    debugPrint('[Kohera] SsoCallbackServer listening on port $port');

    _timeout = Timer(_timeoutDuration, () {
      if (!_tokenCompleter.isCompleted) {
        debugPrint('[Kohera] SsoCallbackServer timed out');
        _tokenCompleter.completeError(
          SsoException('SSO login timed out. Please try again.'),
        );
        dispose();
      }
    });

    _serve();
    return 'http://127.0.0.1:$port/callback';
  }

  Future<void> launch(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw SsoException('Could not open browser');
    }
  }

  void _serve() {
    _server?.listen((request) async {
      try {
        if (request.method == 'GET' && request.uri.path == '/callback') {
          final loginToken = request.uri.queryParameters['loginToken'];

          if (loginToken != null && loginToken.isNotEmpty) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(_buildSuccessPage());
            unawaited(request.response.close());

            if (!_tokenCompleter.isCompleted) {
              _tokenCompleter.complete(loginToken);
            }
            Future<void>.delayed(
              const Duration(seconds: 1),
              dispose,
            );
          } else {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..headers.contentType = ContentType.html
              ..write(_buildErrorPage());
            unawaited(request.response.close());
          }
          return;
        }

        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        unawaited(request.response.close());
      } catch (e) {
        debugPrint('[Kohera] SsoCallbackServer request error: $e');
        try {
          unawaited(request.response.close());
        } catch (_) {}
      }
    });
  }

  String _buildSuccessPage() => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Login Successful</title>
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
    <h2>Login successful</h2>
    <p>You can close this tab and return to Kohera.</p>
  </div>
</body>
</html>
''';

  String _buildErrorPage() => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Login Failed</title>
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
    <h2>Login failed</h2>
    <p>No login token was received. Please try again from Kohera.</p>
  </div>
</body>
</html>
''';

  void dispose() {
    _timeout?.cancel();
    _timeout = null;
    unawaited(_server?.close(force: true).then((_) {
      debugPrint('[Kohera] SsoCallbackServer shut down');
    }),);
    _server = null;
    if (!_tokenCompleter.isCompleted) {
      _tokenCompleter.completeError(
        SsoException('SSO login was cancelled.'),
      );
    }
  }
}

class SsoException implements Exception {
  SsoException(this.message);
  final String message;

  @override
  String toString() => message;
}

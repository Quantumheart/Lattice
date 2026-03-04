import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

// ── SsoCallbackServer ───────────────────────────────────────────────────────

/// Starts a temporary localhost HTTP server that waits for the SSO callback
/// containing a `loginToken` query parameter.
///
/// Lifecycle:
///   1. Call [start] to bind and get the callback URL.
///   2. Await [tokenFuture] to receive the login token.
///   3. Call [dispose] to shut down (safe to call multiple times).
class SsoCallbackServer {
  HttpServer? _server;
  final Completer<String> _tokenCompleter = Completer<String>();
  Timer? _timeout;

  /// Completes with the login token on success,
  /// or errors with an [SsoException] on failure or timeout.
  Future<String> get tokenFuture => _tokenCompleter.future;

  static const _timeoutDuration = Duration(minutes: 5);

  /// Binds to a random localhost port.
  /// Returns the callback URL to pass as `redirectUrl` to the SSO endpoint.
  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = _server!.port;
    debugPrint('[Lattice] SsoCallbackServer listening on port $port');

    _timeout = Timer(_timeoutDuration, () {
      if (!_tokenCompleter.isCompleted) {
        debugPrint('[Lattice] SsoCallbackServer timed out');
        _tokenCompleter.completeError(
          SsoException('SSO login timed out. Please try again.'),
        );
        dispose();
      }
    });

    _serve();
    return 'http://127.0.0.1:$port/callback';
  }

  void _serve() {
    _server?.listen((HttpRequest request) async {
      try {
        if (request.method == 'GET' && request.uri.path == '/callback') {
          final loginToken = request.uri.queryParameters['loginToken'];

          if (loginToken != null && loginToken.isNotEmpty) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(_buildSuccessPage())
              ..close();

            if (!_tokenCompleter.isCompleted) {
              _tokenCompleter.complete(loginToken);
            }
            Future<void>.delayed(
              const Duration(seconds: 1),
              () => dispose(),
            );
          } else {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..headers.contentType = ContentType.html
              ..write(_buildErrorPage())
              ..close();
          }
          return;
        }

        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
      } catch (e) {
        debugPrint('[Lattice] SsoCallbackServer request error: $e');
        try {
          request.response.close();
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
    <p>You can close this tab and return to Lattice.</p>
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
    <p>No login token was received. Please try again from Lattice.</p>
  </div>
</body>
</html>
''';

  void dispose() {
    _timeout?.cancel();
    _timeout = null;
    _server?.close(force: true).then((_) {
      debugPrint('[Lattice] SsoCallbackServer shut down');
    });
    _server = null;
    if (!_tokenCompleter.isCompleted) {
      _tokenCompleter.completeError(
        SsoException('SSO login was cancelled.'),
      );
    }
  }
}

/// Exception thrown when the SSO callback flow fails or is cancelled.
class SsoException implements Exception {
  SsoException(this.message);
  final String message;

  @override
  String toString() => message;
}

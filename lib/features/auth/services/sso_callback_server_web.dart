import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

// ── SsoCallbackServer (Web) ─────────────────────────────────────────────────

class SsoCallbackServer {
  SsoCallbackServer({this.homeserver});

  final String? homeserver;
  final Completer<String> _tokenCompleter = Completer<String>();
  Timer? _timeout;

  Future<String> get tokenFuture => _tokenCompleter.future;

  static const _timeoutDuration = Duration(minutes: 5);
  static const _storageKey = 'kohera_sso_homeserver';

  Future<String> start() async {
    _timeout = Timer(_timeoutDuration, () {
      if (!_tokenCompleter.isCompleted) {
        debugPrint('[Kohera] SsoCallbackServer timed out');
        _tokenCompleter.completeError(
          SsoException('SSO login timed out. Please try again.'),
        );
      }
    });

    final base = Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.port,
      path: base.path,
    ).toString();
  }

  Future<void> launch(Uri url) async {
    if (homeserver != null) {
      web.window.sessionStorage.setItem(_storageKey, homeserver!);
    }
    debugPrint('[Kohera] Redirecting to SSO: $url');
    web.window.location.href = url.toString();
  }

  void dispose() {
    _timeout?.cancel();
    _timeout = null;
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

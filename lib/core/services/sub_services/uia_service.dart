import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

class UiaService {
  UiaService({
    required Client client,
  })  : _client = client;

  final Client _client;

  // ── UIA (User-Interactive Authentication) ──────────────────────
  String? _cachedPassword;
  Timer? _passwordExpiryTimer;

  final _uiaController = StreamController<UiaRequest<dynamic>>.broadcast();
  Stream<UiaRequest<dynamic>> get onUiaRequest => _uiaController.stream;

  StreamSubscription<UiaRequest<dynamic>>? _uiaSub;

  void listenForUia() {
    unawaited(_uiaSub?.cancel());
    _uiaSub = _client.onUiaRequest.stream.listen(_handleUiaRequest);
  }

  Future<void> _handleUiaRequest(UiaRequest<dynamic> uiaRequest) async {
    if (uiaRequest.state != UiaRequestState.waitForUser ||
        uiaRequest.nextStages.isEmpty) {
      return;
    }

    final stage = uiaRequest.nextStages.first;
    debugPrint('[Kohera] UIA request: stage=$stage');

    switch (stage) {
      case AuthenticationTypes.password:
        final password = _cachedPassword;
        final userId = _client.userID;
        if (password != null && userId != null) {
          debugPrint('[Kohera] UIA: completing with cached password');
          return uiaRequest.completeStage(
            AuthenticationPassword(
              session: uiaRequest.session,
              password: password,
              identifier: AuthenticationUserIdentifier(user: userId),
            ),
          );
        }
        debugPrint('[Kohera] UIA: no cached password, forwarding to UI');
        _uiaController.add(uiaRequest);
      case AuthenticationTypes.dummy:
        return uiaRequest.completeStage(
          AuthenticationData(
            type: AuthenticationTypes.dummy,
            session: uiaRequest.session,
          ),
        );
      default:
        debugPrint('[Kohera] UIA: unsupported stage $stage, cancelling');
        uiaRequest.cancel();
    }
  }

  void completeUiaWithPassword(UiaRequest<dynamic> request, String password) {
    final userId = _client.userID;
    if (userId == null) return;
    setCachedPassword(password);
    unawaited(
      request.completeStage(
        AuthenticationPassword(
          session: request.session,
          password: password,
          identifier: AuthenticationUserIdentifier(user: userId),
        ),
      ),
    );
  }

  void setCachedPassword(String password) {
    _cachedPassword = password;
    _passwordExpiryTimer?.cancel();
    _passwordExpiryTimer = Timer(const Duration(seconds: 30), () {
      _cachedPassword = null;
      _passwordExpiryTimer = null;
    });
  }

  void clearCachedPassword() {
    _cachedPassword = null;
    _passwordExpiryTimer?.cancel();
    _passwordExpiryTimer = null;
  }

  void cancelUiaSub() {
    unawaited(_uiaSub?.cancel());
  }

  void dispose() {
    unawaited(_uiaController.close());
    _passwordExpiryTimer?.cancel();
    cancelUiaSub();
  }
}

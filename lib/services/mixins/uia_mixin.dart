import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// User-Interactive Authentication (UIA) handling: cached password,
/// stream controller, and automatic stage completion.
mixin UiaMixin on ChangeNotifier {
  Client get client;

  // ── UIA (User-Interactive Authentication) ──────────────────────
  String? _cachedPassword;
  Timer? _passwordExpiryTimer;

  /// Expose UIA requests that need user interaction (e.g. password prompt).
  /// The UI should listen to this and call [completeUiaWithPassword].
  final _uiaController = StreamController<UiaRequest>.broadcast();
  Stream<UiaRequest> get onUiaRequest => _uiaController.stream;

  StreamSubscription? _uiaSub;

  /// Start listening for UIA requests from the client.
  @protected
  void listenForUia() {
    _uiaSub?.cancel();
    _uiaSub = client.onUiaRequest.stream.listen(_handleUiaRequest);
  }

  Future<void> _handleUiaRequest(UiaRequest uiaRequest) async {
    if (uiaRequest.state != UiaRequestState.waitForUser ||
        uiaRequest.nextStages.isEmpty) {
      return;
    }

    final stage = uiaRequest.nextStages.first;
    debugPrint('[Lattice] UIA request: stage=$stage');

    switch (stage) {
      case AuthenticationTypes.password:
        final password = _cachedPassword;
        final userId = client.userID;
        if (password != null && userId != null) {
          debugPrint('[Lattice] UIA: completing with cached password');
          return uiaRequest.completeStage(
            AuthenticationPassword(
              session: uiaRequest.session,
              password: password,
              identifier: AuthenticationUserIdentifier(user: userId),
            ),
          );
        }
        // No cached password — forward to UI for prompting.
        debugPrint('[Lattice] UIA: no cached password, forwarding to UI');
        _uiaController.add(uiaRequest);
        break;
      case AuthenticationTypes.dummy:
        return uiaRequest.completeStage(
          AuthenticationData(
            type: AuthenticationTypes.dummy,
            session: uiaRequest.session,
          ),
        );
      default:
        debugPrint('[Lattice] UIA: unsupported stage $stage, cancelling');
        uiaRequest.cancel();
    }
  }

  /// Complete a UIA request with the user's password.
  void completeUiaWithPassword(UiaRequest request, String password) {
    final userId = client.userID;
    if (userId == null) return;
    request.completeStage(
      AuthenticationPassword(
        session: request.session,
        password: password,
        identifier: AuthenticationUserIdentifier(user: userId),
      ),
    );
  }

  /// Cache the password with an auto-expiry so it doesn't linger in memory
  /// indefinitely if the user never runs bootstrap.
  @protected
  void setCachedPassword(String password) {
    _cachedPassword = password;
    _passwordExpiryTimer?.cancel();
    _passwordExpiryTimer = Timer(const Duration(minutes: 5), () {
      _cachedPassword = null;
      _passwordExpiryTimer = null;
    });
  }

  /// Clear the cached login password from memory.
  /// Should be called after bootstrap completes to minimize exposure.
  void clearCachedPassword() {
    _cachedPassword = null;
    _passwordExpiryTimer?.cancel();
    _passwordExpiryTimer = null;
  }

  /// Cancel UIA subscription (e.g. on logout or dispose).
  @protected
  void cancelUiaSub() {
    _uiaSub?.cancel();
  }

  /// Close the UIA stream controller (on dispose).
  @protected
  void disposeUiaController() {
    _uiaController.close();
    _passwordExpiryTimer?.cancel();
  }
}

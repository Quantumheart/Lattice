import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/client_manager.dart';
import '../services/matrix_service.dart';
import '../services/sso_callback_server.dart';

// ── LoginState ──────────────────────────────────────────────────────────────

/// States for the login screen state machine.
enum LoginState {
  checkingServer,
  serverError,
  formReady,
  loggingIn,
  ssoInProgress,
  done,
}

// ── LoginController ─────────────────────────────────────────────────────────

/// Business logic for the login flow.
///
/// Follows the same ChangeNotifier state-machine pattern as
/// [RegistrationController]. The screen listens to [notifyListeners]
/// and reads the public getters.
class LoginController extends ChangeNotifier {
  LoginController({
    required this.matrixService,
    required this.clientManager,
    required String homeserver,
  }) : _homeserver = homeserver;

  final MatrixService matrixService;
  final ClientManager clientManager;

  String _homeserver;

  // ── State fields ──────────────────────────────────────────────

  LoginState _state = LoginState.checkingServer;
  LoginState get state => _state;

  String? _error;
  String? get error => _error;

  ServerAuthCapabilities? _capabilities;

  bool get supportsPassword => _capabilities?.supportsPassword ?? false;
  bool get supportsSso => _capabilities?.supportsSso ?? false;
  List<SsoIdentityProvider> get ssoProviders =>
      _capabilities?.ssoIdentityProviders ?? [];

  bool _isDisposed = false;
  int _checkGeneration = 0;

  SsoCallbackServer? _ssoServer;

  // ── Server check ──────────────────────────────────────────────

  Future<void> updateHomeserver(String newHomeserver) async {
    _homeserver = newHomeserver;
    _error = null;
    await checkServer();
  }

  Future<void> checkServer() async {
    // Don't probe while SSO or password login is in progress — the
    // shared client would race with the login flow.
    if (_state == LoginState.ssoInProgress ||
        _state == LoginState.loggingIn) {
      return;
    }

    _state = LoginState.checkingServer;
    _capabilities = null;
    _notify();

    final generation = ++_checkGeneration;

    try {
      final caps =
          await matrixService.getServerAuthCapabilities(_homeserver);
      if (_isDisposed || generation != _checkGeneration) return;

      _capabilities = caps;

      if (!caps.supportsPassword && !caps.supportsSso) {
        _state = LoginState.serverError;
        _error = 'This server does not support password or SSO login';
      } else {
        _state = LoginState.formReady;
      }
      _notify();
    } catch (e) {
      if (_isDisposed || generation != _checkGeneration) return;
      _state = LoginState.serverError;
      _error = _friendlyError(e);
      _notify();
    }
  }

  // ── Password login ────────────────────────────────────────────

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    _error = null;
    _state = LoginState.loggingIn;
    _notify();

    final success = await matrixService.login(
      homeserver: _homeserver,
      username: username,
      password: password,
    );

    if (_isDisposed) return false;

    if (success) {
      if (!clientManager.services.contains(matrixService)) {
        await clientManager.addService(matrixService);
      }
      _state = LoginState.done;
      _notify();
      return true;
    } else {
      _error = matrixService.loginError;
      _state = LoginState.formReady;
      _notify();
      return false;
    }
  }

  // ── SSO login ─────────────────────────────────────────────────

  /// Starts the SSO flow for a specific provider, or the default SSO
  /// redirect if [providerId] is null.
  Future<void> startSsoLogin({String? providerId}) async {
    _error = null;
    _state = LoginState.ssoInProgress;
    _notify();

    _ssoServer?.dispose();

    final server = SsoCallbackServer();
    _ssoServer = server;

    try {
      final callbackUrl = await server.start();

      // Use the resolved homeserver from the server check to avoid
      // calling checkHomeserver on the shared client concurrently.
      final resolvedHs = _capabilities?.resolvedHomeserver
              ?.toString()
              .replaceAll(RegExp(r'/$'), '') ??
          (_homeserver.trim().startsWith('http')
              ? _homeserver.trim()
              : 'https://${_homeserver.trim()}');

      // Build the SSO redirect URL per the Matrix spec.
      final basePath = providerId != null
          ? '$resolvedHs/_matrix/client/v3/login/sso/redirect/$providerId'
          : '$resolvedHs/_matrix/client/v3/login/sso/redirect';

      final ssoUrl = Uri.parse(basePath).replace(
        queryParameters: {'redirectUrl': callbackUrl},
      );

      debugPrint('[Lattice] Opening SSO URL: $ssoUrl');

      if (!await launchUrl(ssoUrl, mode: LaunchMode.externalApplication)) {
        throw SsoException('Could not open browser');
      }

      // Wait for the callback with the login token.
      final loginToken = await server.tokenFuture;
      _ssoServer = null;

      if (_isDisposed) return;

      // Complete the SSO login.
      final success = await matrixService.completeSsoLogin(
        homeserver: _homeserver,
        loginToken: loginToken,
      );

      if (_isDisposed) return;

      if (success) {
        if (!clientManager.services.contains(matrixService)) {
          await clientManager.addService(matrixService);
        }
        _state = LoginState.done;
      } else {
        _error = matrixService.loginError;
        _state = LoginState.formReady;
      }
      _notify();
    } on SsoException catch (e) {
      if (_isDisposed) return;
      _ssoServer = null;
      _error = e.message;
      _state = LoginState.formReady;
      _notify();
    } catch (e) {
      if (_isDisposed) return;
      _ssoServer = null;
      _error = _friendlyError(e);
      _state = LoginState.formReady;
      _notify();
    }
  }

  void cancelSso() {
    _ssoServer?.dispose();
    _ssoServer = null;
    _state = LoginState.formReady;
    _notify();
  }

  // ── Helpers ───────────────────────────────────────────────────

  static String _friendlyError(Object e) {
    if (e is SocketException) return 'Could not reach server';
    if (e is TimeoutException) return 'Connection timed out';
    if (e is FormatException) return 'Invalid server response';
    return e.toString();
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _ssoServer?.dispose();
    _ssoServer = null;
    super.dispose();
  }
}

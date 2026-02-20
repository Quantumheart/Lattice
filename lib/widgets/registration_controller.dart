import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/matrix_service.dart';
import '../services/recaptcha_server.dart';

/// States for the registration flow state machine.
enum RegistrationState {
  checkingServer,
  registrationDisabled,
  formReady,
  enterEmail,
  recaptcha,
  acceptTerms,
  registering,
  done,
  error,
}

/// Business logic for the registration flow.
///
/// Follows the same ChangeNotifier state-machine pattern as
/// [BootstrapController]. The screen listens to [notifyListeners]
/// and reads the public getters.
class RegistrationController extends ChangeNotifier {
  RegistrationController({
    required this.matrixService,
    required String homeserver,
  }) : _homeserver = homeserver;

  final MatrixService matrixService;

  String _homeserver;
  String get homeserver => _homeserver;

  // ── State fields ──────────────────────────────────────────────

  RegistrationState _state = RegistrationState.checkingServer;
  RegistrationState get state => _state;

  String? _error;
  String? get error => _error;

  String? _usernameError;
  String? get usernameError => _usernameError;

  String? _passwordError;
  String? get passwordError => _passwordError;

  String? _tokenError;
  String? get tokenError => _tokenError;

  String _username = '';
  String _password = '';
  String _token = '';

  List<String> _registrationStages = [];

  /// Whether the server requires a registration token.
  bool get requiresToken =>
      _registrationStages.contains('m.login.registration_token');

  // UIA tracking
  String? _session;
  List<List<String>> _flows = [];
  List<String> _completedStages = [];
  Map<String, dynamic> _uiaParams = {};

  // ── reCAPTCHA ───────────────────────────────────────────────
  RecaptchaServer? _recaptchaServer;
  bool _recaptchaWaiting = false;

  /// True while the system browser is open waiting for the user.
  bool get recaptchaWaiting => _recaptchaWaiting;

  /// Public key for the reCAPTCHA widget, from UIA params.
  String? get recaptchaPublicKey {
    final p = _uiaParams['m.login.recaptcha'];
    return p is Map ? p['public_key'] as String? : null;
  }

  /// Policy list from UIA params for the Terms of Service stage.
  List<({String name, String url})> get termsOfServicePolicies {
    final termsParams = _uiaParams['m.login.terms'];
    if (termsParams is! Map) return const [];
    final policies = termsParams['policies'];
    if (policies is! Map) return const [];

    final result = <({String name, String url})>[];
    for (final entry in policies.entries) {
      final policy = entry.value;
      if (policy is! Map) continue;
      // Each policy has locale keys (e.g. 'en') mapping to {name, url},
      // plus a 'version' key (String). Find the first locale entry.
      for (final localeEntry in policy.entries) {
        if (localeEntry.value is! Map) continue;
        final localised = localeEntry.value as Map;
        final name = localised['name'] as String?;
        final url = localised['url'] as String?;
        if (name != null && url != null) {
          result.add((name: name, url: url));
          break;
        }
      }
    }
    return result;
  }

  bool _isDisposed = false;

  /// Whether the server has been checked and supports registration.
  bool get serverReady => _state == RegistrationState.formReady;

  // ── Server check ──────────────────────────────────────────────

  int _checkGeneration = 0;

  Future<void> updateHomeserver(String newHomeserver) async {
    _homeserver = newHomeserver;
    _usernameError = null;
    _passwordError = null;
    _tokenError = null;
    _error = null;
    await checkServer();
  }

  Future<void> checkServer() async {
    _state = RegistrationState.checkingServer;
    _notify();

    final generation = ++_checkGeneration;

    try {
      final caps =
          await matrixService.getServerAuthCapabilities(_homeserver);
      if (_isDisposed || generation != _checkGeneration) return;

      if (!caps.supportsRegistration) {
        _state = RegistrationState.registrationDisabled;
        _registrationStages = const [];
      } else {
        _registrationStages = caps.registrationStages;
        _state = RegistrationState.formReady;
      }
      _notify();
    } catch (e) {
      if (_isDisposed || generation != _checkGeneration) return;
      _state = RegistrationState.error;
      _error = e.toString();
      _notify();
    }
  }

  // ── Form submission ─────────────────────────────────────────────

  Future<void> submitForm({
    required String username,
    required String password,
    String token = '',
  }) async {
    if (_state != RegistrationState.formReady) return;

    _usernameError = null;
    _passwordError = null;
    _tokenError = null;
    _error = null;

    if (username.trim().isEmpty) {
      _usernameError = 'Please enter a username';
      _notify();
      return;
    }
    if (password.isEmpty) {
      _passwordError = 'Please enter a password';
      _notify();
      return;
    }
    if (password.length < 8) {
      _passwordError = 'Password must be at least 8 characters';
      _notify();
      return;
    }
    if (requiresToken && token.trim().isEmpty) {
      _tokenError = 'Please enter a registration token';
      _notify();
      return;
    }

    _username = username.trim();
    _password = password;
    _token = token.trim();

    _state = RegistrationState.registering;
    _notify();

    // Ensure the client homeserver is set before making API calls.
    var hs = _homeserver.trim();
    if (!hs.startsWith('http')) hs = 'https://$hs';
    try {
      await matrixService.client.checkHomeserver(Uri.parse(hs));
    } catch (e) {
      _state = RegistrationState.error;
      _error = e.toString();
      _notify();
      return;
    }

    if (_isDisposed) return;
    await _attemptRegister();
  }

  Future<void> _attemptRegister({AuthenticationData? auth}) async {
    _state = RegistrationState.registering;
    _notify();

    try {
      final response = await matrixService.client.register(
        username: _username,
        password: _password,
        initialDeviceDisplayName: 'Lattice Flutter',
        auth: auth,
      );

      if (_isDisposed) return;

      await matrixService.completeRegistration(response, password: _password);
      _clearCredentials();
      _state = RegistrationState.done;
      _notify();
    } on MatrixException catch (e) {
      if (_isDisposed) return;

      // UIA challenge — parse flows and advance to next stage.
      if (e.raw.containsKey('flows')) {
        _session = e.raw['session'] as String?;
        _completedStages =
            List<String>.from(e.raw['completed'] as List? ?? []);
        _flows = (e.raw['flows'] as List?)
                ?.map((f) =>
                    List<String>.from((f as Map)['stages'] as List? ?? []))
                .toList() ??
            [];
        _uiaParams = Map<String, dynamic>.from(
          e.raw['params'] as Map? ?? {},
        );
        _advanceToNextStage();
        return;
      }

      // Route username/password errors to their respective fields
      // so they display inline rather than as a generic error.
      if (_isUsernameError(e.errcode)) {
        _usernameError = _humanReadableError(e);
        _state = RegistrationState.formReady;
      } else {
        _state = RegistrationState.error;
        _error = _humanReadableError(e);
      }
      _notify();
    } catch (e) {
      if (_isDisposed) return;
      _state = RegistrationState.error;
      _error = _friendlyError(e);
      _notify();
    }
  }

  void _advanceToNextStage() {
    final bestFlow = _findBestFlow();
    final nextStage = bestFlow.firstWhere(
      (s) => !_completedStages.contains(s),
      orElse: () => '',
    );

    switch (nextStage) {
      case AuthenticationTypes.dummy:
        // Auto-complete dummy stage.
        _attemptRegister(
          auth: AuthenticationData(
            type: AuthenticationTypes.dummy,
            session: _session,
          ),
        );
        return;
      case 'm.login.registration_token':
        // Auto-complete with the token collected from the form.
        _attemptRegister(
          auth: _RegistrationTokenAuth(
            session: _session,
            token: _token,
          ),
        );
        return;
      case AuthenticationTypes.emailIdentity:
        _state = RegistrationState.enterEmail;
      case AuthenticationTypes.recaptcha:
        _state = RegistrationState.recaptcha;
      case 'm.login.terms':
        _state = RegistrationState.acceptTerms;
      case '':
        // All stages completed but no success response — shouldn't happen.
        _state = RegistrationState.error;
        _error = 'Registration failed unexpectedly';
      default:
        _state = RegistrationState.error;
        _error = 'Unsupported registration step: $nextStage';
    }
    _notify();
  }

  static const _supportedStages = {
    AuthenticationTypes.dummy,
    AuthenticationTypes.emailIdentity,
    AuthenticationTypes.recaptcha,
    'm.login.terms',
    'm.login.registration_token',
  };

  List<String> _findBestFlow() {
    if (_flows.isEmpty) return [];
    // Prefer flows where all remaining stages are supported, then fewest remaining.
    return _flows.reduce((a, b) {
      final aRemaining = a.where((s) => !_completedStages.contains(s));
      final bRemaining = b.where((s) => !_completedStages.contains(s));
      final aSupported = aRemaining.every((s) => _supportedStages.contains(s));
      final bSupported = bRemaining.every((s) => _supportedStages.contains(s));
      if (aSupported != bSupported) return aSupported ? a : b;
      return aRemaining.length <= bRemaining.length ? a : b;
    });
  }

  // ── reCAPTCHA submission ──────────────────────────────────────

  Future<void> submitRecaptcha() async {
    if (_state != RegistrationState.recaptcha) return;

    final publicKey = recaptchaPublicKey;
    if (publicKey == null || publicKey.isEmpty) {
      _state = RegistrationState.error;
      _error = 'Server did not provide a reCAPTCHA site key';
      _notify();
      return;
    }

    _recaptchaServer?.dispose();

    final server = RecaptchaServer(siteKey: publicKey);
    _recaptchaServer = server;

    try {
      final url = await server.start();
      debugPrint('[Lattice] Opening reCAPTCHA page: $url');

      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('Could not open browser');
      }

      _recaptchaWaiting = true;
      _notify();

      final token = await server.tokenFuture;
      _recaptchaWaiting = false;
      _recaptchaServer = null;

      if (_isDisposed) return;

      await _attemptRegister(
        auth: _RecaptchaAuth(session: _session, response: token),
      );
    } on RecaptchaException catch (e) {
      if (_isDisposed) return;
      _recaptchaWaiting = false;
      _recaptchaServer = null;
      _state = RegistrationState.error;
      _error = e.message;
      _notify();
    } catch (e) {
      if (_isDisposed) return;
      _recaptchaWaiting = false;
      _recaptchaServer = null;
      _state = RegistrationState.error;
      _error = _friendlyError(e);
      _notify();
    }
  }

  // ── Terms submission ────────────────────────────────────────

  Future<void> submitTerms() async {
    if (_state != RegistrationState.acceptTerms) return;

    await _attemptRegister(
      auth: AuthenticationData(
        type: 'm.login.terms',
        session: _session,
      ),
    );
  }

  // ── Error mapping ──────────────────────────────────────────────

  static const _usernameErrcodes = {
    'M_USER_IN_USE',
    'M_INVALID_USERNAME',
    'M_EXCLUSIVE',
  };

  bool _isUsernameError(String? errcode) =>
      _usernameErrcodes.contains(errcode);

  String _humanReadableError(MatrixException e) {
    switch (e.errcode) {
      case 'M_USER_IN_USE':
        return 'This username is already taken';
      case 'M_INVALID_USERNAME':
        return 'Username contains invalid characters';
      case 'M_EXCLUSIVE':
        return 'This username is reserved';
      case 'M_FORBIDDEN':
        return 'Registration is not allowed on this server';
      case 'M_THREEPID_IN_USE':
        return 'This email is already registered';
      case 'M_THREEPID_DENIED':
        return 'This email domain is not allowed';
      default:
        return e.errorMessage;
    }
  }

  /// Converts common non-Matrix exceptions to user-friendly messages.
  static String _friendlyError(Object e) {
    if (e is SocketException) return 'Could not reach server';
    if (e is TimeoutException) return 'Connection timed out';
    if (e is FormatException) return 'Invalid server response';
    return e.toString();
  }

  // ── Cancel ──────────────────────────────────────────────────────

  /// Resets the controller from a UIA dead-end back to [RegistrationState.formReady].
  void cancelRegistration() {
    _recaptchaServer?.dispose();
    _recaptchaServer = null;
    _recaptchaWaiting = false;
    _session = null;
    _flows = [];
    _completedStages = [];
    _uiaParams = {};
    _error = null;
    _state = RegistrationState.formReady;
    _notify();
  }

  // ── Internals ──────────────────────────────────────────────────

  void _clearCredentials() {
    _username = '';
    _password = '';
    _token = '';
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _recaptchaServer?.dispose();
    _recaptchaServer = null;
    _clearCredentials();
    super.dispose();
  }
}

/// [AuthenticationData] subclass for the `m.login.recaptcha` UIA stage.
class _RecaptchaAuth extends AuthenticationData {
  final String _response;

  _RecaptchaAuth({super.session, required String response})
      : _response = response,
        super(type: AuthenticationTypes.recaptcha);

  @override
  Map<String, Object?> toJson() {
    final data = super.toJson();
    data['response'] = _response;
    return data;
  }
}

/// [AuthenticationData] subclass for the `m.login.registration_token` UIA stage.
class _RegistrationTokenAuth extends AuthenticationData {
  final String _token;

  _RegistrationTokenAuth({super.session, required String token})
      : _token = token,
        super(type: 'm.login.registration_token');

  @override
  Map<String, Object?> toJson() {
    final data = super.toJson();
    data['token'] = _token;
    return data;
  }
}

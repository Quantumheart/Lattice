import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

import '../matrix_service.dart' show ServerAuthCapabilities, latticeKey;
import '../session_backup.dart';

/// Authentication flows: login, SSO, registration, logout, credential
/// persistence, server capability probing, and login-state monitoring.
mixin AuthMixin on ChangeNotifier {
  // ── Core dependencies (satisfied by MatrixService) ────────────
  Client get client;
  FlutterSecureStorage get storage;
  String get clientName;
  bool get isLoggedIn;
  set isLoggedIn(bool value);

  // ── Cross-mixin dependencies ──────────────────────────────────
  void listenForUia();
  void setCachedPassword(String password);
  void clearCachedPassword();
  void cancelUiaSub();
  Future<void> startSync();
  void resetSelection();
  void resetChatBackupState();
  Future<void> saveSessionBackup();

  // ── Auth state ────────────────────────────────────────────────
  String? _loginError;
  String? get loginError => _loginError;

  StreamSubscription? _loginStateSub;

  // ── Server Capabilities ──────────────────────────────────────

  /// Query the homeserver for supported login and registration flows.
  ///
  /// Temporarily sets [client.homeserver] for the probe requests and
  /// restores it afterwards. Returns an empty [ServerAuthCapabilities]
  /// if called while logged in to avoid racing with sync.
  Future<ServerAuthCapabilities> getServerAuthCapabilities(
      String homeserver) async {
    if (isLoggedIn) {
      debugPrint('[Lattice] getServerAuthCapabilities called while logged in, '
          'skipping to avoid mutating shared client state');
      return const ServerAuthCapabilities();
    }

    var hs = homeserver.trim();
    if (!hs.startsWith('http')) hs = 'https://$hs';

    final previousHomeserver = client.homeserver;
    try {
      await client.checkHomeserver(Uri.parse(hs));

      // Query login flows.
      final loginFlows = await client.getLoginFlows();
      final supportsPassword =
          loginFlows?.any((f) => f.type == AuthenticationTypes.password) ??
              false;
      final supportsSso =
          loginFlows?.any((f) => f.type == AuthenticationTypes.sso) ?? false;

      // Extract SSO identity providers.
      final ssoFlow = loginFlows
          ?.where((f) => f.type == AuthenticationTypes.sso)
          .firstOrNull;
      final idProviders = <String>[];
      if (ssoFlow != null) {
        final providers = ssoFlow.additionalProperties['identity_providers'];
        if (providers is List) {
          for (final p in providers) {
            if (p is Map && p['name'] is String) {
              idProviders.add(p['name'] as String);
            }
          }
        }
      }

      // Probe registration support.
      var supportsRegistration = false;
      var registrationStages = <String>[];
      try {
        await client.register();
      } on MatrixException catch (e) {
        if (e.raw.containsKey('flows')) {
          supportsRegistration = true;
          final flows = e.raw['flows'];
          if (flows is List && flows.isNotEmpty) {
            final firstFlow = flows.first;
            if (firstFlow is Map && firstFlow['stages'] is List) {
              registrationStages =
                  (firstFlow['stages'] as List).cast<String>();
            }
          }
        }
      } catch (_) {
        // Registration not supported or server error.
      }

      return ServerAuthCapabilities(
        supportsPassword: supportsPassword,
        supportsSso: supportsSso,
        supportsRegistration: supportsRegistration,
        ssoIdentityProviders: idProviders,
        registrationStages: registrationStages,
      );
    } finally {
      client.homeserver = previousHomeserver;
    }
  }

  // ── Login ────────────────────────────────────────────────────
  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    _loginError = null;
    notifyListeners();

    try {
      var hs = homeserver.trim();
      if (!hs.startsWith('http')) hs = 'https://$hs';

      debugPrint('[Lattice] Checking homeserver: $hs');
      client.homeserver = Uri.parse(hs);
      await client.checkHomeserver(Uri.parse(hs));
      debugPrint('[Lattice] Homeserver OK');

      debugPrint('[Lattice] Logging in as $username ...');
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username.trim()),
        password: password,
        initialDeviceDisplayName: 'Lattice Flutter',
      );
      debugPrint('[Lattice] Login complete – '
          'deviceId=${client.deviceID}, '
          'userId=${client.userID}, '
          'encryption=${client.encryption != null ? "available" : "null"}, '
          'encryptionEnabled=${client.encryptionEnabled}');

      await _persistCredentials();

      setCachedPassword(password);
      listenForUia();
      listenForLoginState();
      await startSync();
      isLoggedIn = true;

      // Write session backup after successful login + first sync.
      await saveSessionBackup();

      notifyListeners();
      return true;
    } catch (e, s) {
      debugPrint('[Lattice] Login failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      _loginError = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── SSO Login ──────────────────────────────────────────────────

  /// Complete an SSO login using a login token received from the browser
  /// callback. Call this after the user authenticates via SSO.
  Future<bool> completeSsoLogin({
    required String homeserver,
    required String loginToken,
  }) async {
    _loginError = null;
    notifyListeners();

    try {
      var hs = homeserver.trim();
      if (!hs.startsWith('http')) hs = 'https://$hs';

      client.homeserver = Uri.parse(hs);
      await client.checkHomeserver(Uri.parse(hs));

      debugPrint('[Lattice] Completing SSO login ...');
      await client.login(
        LoginType.mLoginToken,
        token: loginToken,
        initialDeviceDisplayName: 'Lattice Flutter',
      );
      debugPrint('[Lattice] SSO login complete – '
          'deviceId=${client.deviceID}, '
          'userId=${client.userID}');

      await _persistCredentials();
      listenForUia();
      listenForLoginState();
      await startSync();
      isLoggedIn = true;

      await saveSessionBackup();

      notifyListeners();
      return true;
    } catch (e, s) {
      debugPrint('[Lattice] SSO login failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      _loginError = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Registration ──────────────────────────────────────────────

  /// Complete a successful registration by persisting credentials and
  /// starting sync. The SDK's [Client.register] already calls
  /// [Client.init] internally, so the client is initialized by the time
  /// we reach here — we just persist and start syncing.
  Future<void> completeRegistration(RegisterResponse response) async {
    debugPrint('[Lattice] Registration complete – userId=${response.userId}');

    if (client.accessToken == null || client.userID == null) {
      throw StateError(
          'Client was not initialized after register(). '
          'accessToken=${client.accessToken}, userID=${client.userID}');
    }

    await _persistCredentials();
    listenForUia();
    listenForLoginState();
    await startSync();
    isLoggedIn = true;

    await saveSessionBackup();

    notifyListeners();
  }

  // ── Credential Persistence ──────────────────────────────────

  Future<void> _persistCredentials() async {
    await storage.write(
        key: latticeKey(clientName, 'access_token'),
        value: client.accessToken);
    await storage.write(
        key: latticeKey(clientName, 'user_id'), value: client.userID);
    await storage.write(
        key: latticeKey(clientName, 'homeserver'),
        value: client.homeserver.toString());
    await storage.write(
        key: latticeKey(clientName, 'device_id'), value: client.deviceID);
  }

  // ── Logout ───────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      if (client.homeserver != null && client.accessToken != null) {
        await client.logout();
      }
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    await clearSessionKeys();
    await SessionBackup.delete(clientName: clientName, storage: storage);
    isLoggedIn = false;
    clearCachedPassword();
    cancelUiaSub();
    _loginStateSub?.cancel();
    resetSelection();
    resetChatBackupState();
    notifyListeners();
  }

  // ── Soft Logout ──────────────────────────────────────────────

  @protected
  Future<void> handleSoftLogout() async {
    debugPrint('[Lattice] Soft logout detected, attempting token refresh...');
    try {
      await client.refreshAccessToken();
      // Update stored token + session backup with new token.
      await storage.write(
          key: latticeKey(clientName, 'access_token'),
          value: client.accessToken);
      await saveSessionBackup();
      debugPrint('[Lattice] Token refreshed successfully');
    } catch (e) {
      debugPrint('[Lattice] Token refresh failed: $e');
      isLoggedIn = false;
      await clearSessionKeys();
      await SessionBackup.delete(clientName: clientName, storage: storage);
      try {
        await client.logout();
      } catch (_) {
        // Logout may fail since the token is already invalid; just ensure
        // the local session is cleared so the SDK stops retrying.
      }
      notifyListeners();
    }
  }

  // ── Login State Stream ────────────────────────────────────────

  @protected
  void listenForLoginState() {
    _loginStateSub?.cancel();
    _loginStateSub = client.onLoginStateChanged.stream.listen((state) {
      if (state == LoginState.loggedOut && isLoggedIn) {
        debugPrint('[Lattice] Server-side logout detected');
        isLoggedIn = false;
        resetSelection();
        resetChatBackupState();
        clearSessionKeys();
        SessionBackup.delete(clientName: clientName, storage: storage);
        notifyListeners();
      }
    });
  }

  // ── Session Key Management ────────────────────────────────────

  /// Returns true if the error indicates the stored session is permanently
  /// invalid (e.g. token revoked, unknown device). Transient network errors
  /// return false so credentials are preserved for the next app launch.
  @protected
  bool isPermanentAuthFailure(Object error) {
    if (error is MatrixException) {
      // M_SOFT_LOGOUT is not permanent — handled by handleSoftLogout.
      return error.errcode == 'M_UNKNOWN_TOKEN' ||
          error.errcode == 'M_FORBIDDEN' ||
          error.errcode == 'M_USER_DEACTIVATED';
    }
    return false;
  }

  @protected
  Future<void> clearSessionKeys() async {
    await storage.delete(key: latticeKey(clientName, 'access_token'));
    await storage.delete(key: latticeKey(clientName, 'user_id'));
    await storage.delete(key: latticeKey(clientName, 'homeserver'));
    await storage.delete(key: latticeKey(clientName, 'device_id'));
    await storage.delete(key: latticeKey(clientName, 'olm_account'));
  }

  // ── Storage Key Migration ─────────────────────────────────────

  /// One-time migration from old unnamespaced keys to clientName-namespaced keys.
  @protected
  Future<void> migrateStorageKeys() async {
    if (clientName != 'default') return;

    final oldToken = await storage.read(key: 'lattice_access_token');
    if (oldToken == null) return;

    debugPrint('[Lattice] Migrating old storage keys to namespaced format');

    const migrations = {
      'lattice_access_token': 'lattice_default_access_token',
      'lattice_user_id': 'lattice_default_user_id',
      'lattice_homeserver': 'lattice_default_homeserver',
      'lattice_device_id': 'lattice_default_device_id',
      'lattice_olm_account': 'lattice_default_olm_account',
    };

    for (final entry in migrations.entries) {
      final value = await storage.read(key: entry.key);
      if (value != null) {
        await storage.write(key: entry.value, value: value);
        await storage.delete(key: entry.key);
      }
    }
  }

  /// Cancel login-state subscription (e.g. on dispose).
  @protected
  void cancelLoginStateSub() {
    _loginStateSub?.cancel();
  }
}

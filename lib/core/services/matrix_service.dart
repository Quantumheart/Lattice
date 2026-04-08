import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lattice/core/services/session_backup.dart';
import 'package:lattice/core/services/sub_services/auth_service.dart';
import 'package:lattice/core/services/sub_services/chat_backup_service.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/core/services/sub_services/sync_service.dart';
import 'package:lattice/core/services/sub_services/uia_service.dart';
import 'package:lattice/core/utils/network_error.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports, no public API for ClientInitException
import 'package:matrix/src/utils/client_init_exception.dart';

String latticeKey(String clientName, String suffix) =>
    'lattice_${clientName}_$suffix';

class MatrixService extends ChangeNotifier {
  static String friendlyAuthError(Object e) {
    if (isNetworkError(e)) return 'Could not reach server';
    if (e is TimeoutException) return 'Connection timed out';
    if (e is FormatException) return 'Invalid server response';
    return e.toString();
  }

  MatrixService({
    required Client client,
    FlutterSecureStorage? storage,
    this.clientName = 'default',
  })  : _client = client,
        _storage = storage ??
            const FlutterSecureStorage(
              webOptions: WebOptions(
                dbName: 'LatticeEncryptedStorage',
                publicKey: 'LatticeSecureStorage',
              ),
            ) {
    uia = UiaService(client: _client);
    chatBackup = ChatBackupService(
      client: _client,
      storage: _storage,
    );
    selection = SelectionService(client: _client);
    sync = SyncService(
      client: _client,
      onPostSyncBackup: () async {
        await chatBackup.checkChatBackupStatus();
        if (chatBackup.chatBackupNeeded == true) {
          await chatBackup.tryAutoUnlockBackup();
        }
      },
    );
    auth = AuthService(
      client: _client,
      storage: _storage,
      clientName: clientName,
    );
  }

  // ── Fields ──────────────────────────────────────────────────────

  final FlutterSecureStorage _storage;
  final String clientName;

  final Client _client;
  Client get client => _client;

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  @visibleForTesting
  set isLoggedInForTest(bool value) => _isLoggedIn = value;

  bool _disposed = false;
  bool get disposed => _disposed;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // ── Sub-services ────────────────────────────────────────────────

  late final UiaService uia;
  late final ChatBackupService chatBackup;
  late final SelectionService selection;
  late final SyncService sync;
  late final AuthService auth;

  StreamSubscription<LoginState>? _loginStateSub;

  bool _hasSkippedSetup = false;
  bool get hasSkippedSetup => _hasSkippedSetup;
  void skipSetup() {
    _hasSkippedSetup = true;
    notifyListeners();
  }

  Future<String?> _readRefreshToken() async {
    final stored = await _client.database.getClient(clientName);
    return stored?.tryGet<String>('refresh_token');
  }

  // ── Public API ──────────────────────────────────────────────────

  Future<void> init({bool restoreSession = true}) async {
    if (restoreSession) await auth.migrateStorageKeys();
    if (restoreSession) {
      await _restoreSession();
      notifyListeners();
    }
  }

  Future<void> saveSessionBackup() async {
    final backup = SessionBackup(
      accessToken: _client.accessToken!,
      refreshToken: await _readRefreshToken(),
      userId: _client.userID!,
      homeserver: _client.homeserver.toString(),
      deviceId: _client.deviceID!,
      deviceName: 'Lattice Flutter',
      olmAccount: _client.encryption?.pickledOlmAccount,
    );
    await SessionBackup.save(
      backup,
      clientName: clientName,
      storage: _storage,
    );
    debugPrint('[Lattice] Session backup saved for $clientName');
  }

  @override
  void dispose() {
    _disposed = true;
    _isLoggedIn = false;
    sync.cancelSyncSub();
    uia.dispose();
    selection.dispose();
    chatBackup.dispose();
    sync.dispose();
    unawaited(_loginStateSub?.cancel());
    super.dispose();
  }

  // ── Login ──────────────────────────────────────────────────────

  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    auth.loginError = null;
    notifyListeners();

    try {
      var hs = homeserver.trim();
      if (hs.isEmpty) throw ArgumentError('Homeserver cannot be empty');
      if (!hs.startsWith('http')) hs = 'https://$hs';

      debugPrint('[Lattice] Checking homeserver: $hs');
      await _client.checkHomeserver(Uri.parse(hs));
      debugPrint('[Lattice] Homeserver OK');

      debugPrint('[Lattice] Logging in as $username ...');
      await _client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username.trim()),
        password: password,
        initialDeviceDisplayName: 'Lattice Flutter',
        refreshToken: true,
      );
      debugPrint('[Lattice] Login complete – '
          'deviceId=${_client.deviceID}, '
          'userId=${_client.userID}, '
          'encryption=${_client.encryption != null ? "available" : "null"}, '
          'encryptionEnabled=${_client.encryptionEnabled}');

      uia.setCachedPassword(password);
      uia.listenForUia();
      _listenForLoginState();
      _isLoggedIn = true;
      notifyListeners();

      _postLoginSync();

      return true;
    } catch (e, s) {
      debugPrint('[Lattice] Login failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      auth.loginError = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── SSO Login ──────────────────────────────────────────────────

  Future<bool> completeSsoLogin({
    required String homeserver,
    required String loginToken,
  }) async {
    auth.loginError = null;
    notifyListeners();

    try {
      var hs = homeserver.trim();
      if (hs.isEmpty) throw ArgumentError('Homeserver cannot be empty');
      if (!hs.startsWith('http')) hs = 'https://$hs';

      await _client.checkHomeserver(Uri.parse(hs));

      debugPrint('[Lattice] Completing SSO login ...');
      await _client.login(
        LoginType.mLoginToken,
        token: loginToken,
        initialDeviceDisplayName: 'Lattice Flutter',
        refreshToken: true,
      );
      debugPrint('[Lattice] SSO login complete – '
          'deviceId=${_client.deviceID}, '
          'userId=${_client.userID}');

      uia.listenForUia();
      _listenForLoginState();
      _isLoggedIn = true;
      notifyListeners();

      _postLoginSync();

      return true;
    } catch (e, s) {
      debugPrint('[Lattice] SSO login failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      auth.loginError = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Registration ──────────────────────────────────────────────

  Future<void> completeRegistration(
    RegisterResponse response, {
    String? password,
  }) async {
    debugPrint('[Lattice] Registration complete – userId=${response.userId}');

    if (_client.accessToken == null || _client.userID == null) {
      throw StateError('Client was not initialized after register(). '
          'accessToken=${_client.accessToken}, userID=${_client.userID}');
    }

    if (password != null) uia.setCachedPassword(password);
    uia.listenForUia();
    _listenForLoginState();
    _isLoggedIn = true;
    notifyListeners();

    _postLoginSync();
  }

  // ── Logout ────────────────────────────────────────────────────

  Future<void> logout() async {
    unawaited(_loginStateSub?.cancel());
    sync.cancelSyncSub();
    _isLoggedIn = false;
    await auth.awaitPostLoginSync();

    try {
      if (_client.homeserver != null && _client.accessToken != null) {
        await _client.logout();
      }
    } catch (e) {
      debugPrint('[Lattice] Logout error: $e');
    }
    await auth.clearSessionKeys();
    await SessionBackup.delete(clientName: clientName, storage: _storage);
    await chatBackup.deleteStoredRecoveryKey();
    uia.clearCachedPassword();
    uia.cancelUiaSub();
    selection.resetSelection();
    chatBackup.resetChatBackupState();
    _hasSkippedSetup = false;
    notifyListeners();
  }

  // ── Soft Logout ──────────────────────────────────────────────

  Future<void> handleSoftLogout() async {
    debugPrint('[Lattice] Soft logout detected, attempting token refresh...');
    try {
      await _client.refreshAccessToken();
      final refreshToken = await _readRefreshToken();
      await Future.wait([
        _storage.write(
          key: latticeKey(clientName, 'access_token'),
          value: _client.accessToken,
        ),
        _storage.write(
          key: latticeKey(clientName, 'refresh_token'),
          value: refreshToken,
        ),
      ]);
      await saveSessionBackup();
      debugPrint('[Lattice] Token refreshed successfully');
    } catch (e) {
      debugPrint('[Lattice] Token refresh failed: $e');
      unawaited(_loginStateSub?.cancel());
      sync.cancelSyncSub();
      _isLoggedIn = false;
      await auth.awaitPostLoginSync();
      uia.cancelUiaSub();
      uia.clearCachedPassword();
      selection.resetSelection();
      chatBackup.resetChatBackupState();
      _hasSkippedSetup = false;
      await auth.clearSessionKeys();
      await SessionBackup.delete(clientName: clientName, storage: _storage);
      await chatBackup.deleteStoredRecoveryKey();
      try {
        await _client.logout();
      } catch (_) {}
      notifyListeners();
    }
  }

  // ── Private: Login State Stream ─────────────────────────────────

  void _listenForLoginState() {
    unawaited(_loginStateSub?.cancel());
    _loginStateSub = _client.onLoginStateChanged.stream.listen((state) async {
      if (state == LoginState.loggedOut && _isLoggedIn) {
        debugPrint('[Lattice] Server-side logout detected');
        unawaited(_loginStateSub?.cancel());
        _loginStateSub = null;
        sync.cancelSyncSub();
        _isLoggedIn = false;
        uia.cancelUiaSub();
        uia.clearCachedPassword();
        selection.resetSelection();
        chatBackup.resetChatBackupState();
        _hasSkippedSetup = false;
        await auth.clearSessionKeys();
        await SessionBackup.delete(clientName: clientName, storage: _storage);
        await chatBackup.deleteStoredRecoveryKey();
        notifyListeners();
      }
    });
  }

  // ── Private: Post-login Background Sync ─────────────────────────

  void _postLoginSync() {
    auth.startPostLoginSync(_runPostLoginSync);
  }

  Future<void> _runPostLoginSync() async {
    try {
      try {
        await auth.persistCredentials();
      } catch (e) {
        debugPrint('[Lattice] Credential persistence failed (non-fatal): $e');
      }
      if (!_isLoggedIn) return;
      await sync.startSync(timeout: const Duration(minutes: 5));
      if (!_isLoggedIn) return;
      await saveSessionBackup();
    } catch (e) {
      debugPrint('[Lattice] Post-login sync error: $e');
      if (_isLoggedIn) {
        auth.postLoginSyncError = friendlyAuthError(e);
        notifyListeners();
      }
    }
  }

  // ── Private: Initialization ─────────────────────────────────────

  Future<void> _activateSession() async {
    uia.listenForUia();
    _listenForLoginState();
    _isLoggedIn = true;
    try {
      await sync.startSync();
    } on TimeoutException {
      debugPrint('[Lattice] Initial sync timed out during session restore – '
          'continuing in background');
    }
  }

  // ── Private: Session Keys ──────────────────────────────────────

  Future<void> _clearSessionAndBackup() async {
    await auth.clearSessionKeys();
    await SessionBackup.delete(clientName: clientName, storage: _storage);
  }

  Future<
      ({
        String? token,
        String? refreshToken,
        String? userId,
        String? homeserver,
        String? deviceId
      })> _readSessionKeys() async {
    final results = await Future.wait([
      _storage.read(key: latticeKey(clientName, 'access_token')),
      _storage.read(key: latticeKey(clientName, 'refresh_token')),
      _storage.read(key: latticeKey(clientName, 'user_id')),
      _storage.read(key: latticeKey(clientName, 'homeserver')),
      _storage.read(key: latticeKey(clientName, 'device_id')),
    ]);
    return (
      token: results[0],
      refreshToken: results[1],
      userId: results[2],
      homeserver: results[3],
      deviceId: results[4],
    );
  }

  // ── Private: Session Restore ───────────────────────────────────

  Future<void> _restoreSession() async {
    final ({
      String? token,
      String? refreshToken,
      String? userId,
      String? homeserver,
      String? deviceId
    }) keys;
    try {
      keys = await _readSessionKeys();
    } catch (e) {
      debugPrint('[Lattice] Failed to read session keys: $e');
      return;
    }

    if (keys.token == null || keys.userId == null || keys.homeserver == null) {
      await _tryDatabaseRestore();
      return;
    }

    final backup = await SessionBackup.load(
      clientName: clientName,
      storage: _storage,
    );

    debugPrint(
        '[Lattice] Restoring session for ${keys.userId} on ${keys.homeserver} '
        '(deviceId=${keys.deviceId}, clientName=$clientName)');

    try {
      final homeserverUri = Uri.parse(keys.homeserver!);
      _client.homeserver = homeserverUri;
      await _client.init(
        newToken: keys.token,
        newRefreshToken: keys.refreshToken ?? backup?.refreshToken,
        newUserID: keys.userId,
        newDeviceID: keys.deviceId,
        newHomeserver: homeserverUri,
        newDeviceName: 'Lattice Flutter',
        newOlmAccount: backup?.olmAccount,
      );
      debugPrint('[Lattice] Session restored – '
          'encryption=${_client.encryption != null ? "available" : "null"}, '
          'encryptionEnabled=${_client.encryptionEnabled}');
      await _activateSession();
      await saveSessionBackup();
    } catch (e, s) {
      debugPrint('[Lattice] Session restore failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');

      final cause = _unwrapInitException(e);

      if (_isExpiredTokenError(cause)) {
        final refreshed = await _tryDatabaseRestore();
        if (refreshed) return;
      }

      _isLoggedIn = false;
      if (auth.isPermanentAuthFailure(cause)) {
        await _clearSessionAndBackup();
      }
    }
  }

  Future<bool> _tryDatabaseRestore() async {
    debugPrint('[Lattice] Attempting database-only restore (token refresh)...');
    try {
      await _client.init();
      if (_client.isLogged()) {
        if (_client.accessToken != null) {
          final refreshToken = await _readRefreshToken();
          await Future.wait([
            _storage.write(
              key: latticeKey(clientName, 'access_token'),
              value: _client.accessToken,
            ),
            _storage.write(
              key: latticeKey(clientName, 'refresh_token'),
              value: refreshToken,
            ),
          ]);
        }
        await _activateSession();
        await saveSessionBackup();
        debugPrint('[Lattice] Session restored via database token refresh');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Lattice] Database-only restore failed: $e');
      return false;
    }
  }

  // ── Private: Error Classification ──────────────────────────────

  static Object _unwrapInitException(Object e) =>
      e is ClientInitException ? e.originalException : e;

  static bool _isExpiredTokenError(Object e) {
    if (e is MatrixException && e.errcode == 'M_UNKNOWN_TOKEN') {
      return e.errorMessage.toLowerCase().contains('expired');
    }
    return false;
  }
}

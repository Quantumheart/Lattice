import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/core/services/session_backup.dart';
import 'package:kohera/core/services/sub_services/auth_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/sync_service.dart';
import 'package:kohera/core/services/sub_services/uia_service.dart';
import 'package:kohera/core/utils/network_error.dart';
import 'package:kohera/features/notifications/services/call_push_rule_manager.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports, no public API for ClientInitException
import 'package:matrix/src/utils/client_init_exception.dart';

String koheraKey(String clientName, String suffix) =>
    'kohera_${clientName}_$suffix';

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
              iOptions: IOSOptions(
                groupId: 'group.io.github.quantumheart.kohera',
                accessibility: KeychainAccessibility.first_unlock,
              ),
              webOptions: WebOptions(
                dbName: 'KoheraEncryptedStorage',
                publicKey: 'KoheraSecureStorage',
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
        await chatBackup.tryAutoUnlockBackup();
      },
    );
    auth = AuthService(
      client: _client,
      storage: _storage,
      clientName: clientName,
    );
    callPushRuleManager = CallPushRuleManager(client: _client);
    auth.addListener(_onAuthChanged);
  }

  late final CallPushRuleManager callPushRuleManager;

  // ── Fields ──────────────────────────────────────────────────────

  final FlutterSecureStorage _storage;
  final String clientName;

  final Client _client;
  Client get client => _client;

  bool get isLoggedIn => auth.isLoggedIn;

  @visibleForTesting
  set isLoggedInForTest(bool value) {
    auth.isLoggedIn = value;
    auth.notifyListeners();
  }

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

  @override
  void dispose() {
    _disposed = true;
    auth.removeListener(_onAuthChanged);
    auth.isLoggedIn = false;
    sync.cancelSyncSub();
    uia.dispose();
    selection.dispose();
    chatBackup.dispose();
    sync.dispose();
    unawaited(_loginStateSub?.cancel());
    super.dispose();
  }

  // ── Public API ──────────────────────────────────────────────────

  Future<void> init({bool restoreSession = true}) async {
    if (restoreSession) await auth.migrateStorageKeys();
    if (restoreSession) {
      await _restoreSession();
      notifyListeners();
    }
  }

  // ── Login ──────────────────────────────────────────────────────

  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    final success = await auth.login(
      homeserver: homeserver,
      username: username,
      password: password,
    );
    if (success) {
      uia.setCachedPassword(password);
      try {
        await sync.startSync(timeout: const Duration(minutes: 5));
        await auth.saveSessionBackup();
      } catch (e) {
        debugPrint('[Kohera] Post-login sync error: $e');
      }
    }
    return success;
  }

  // ── SSO Login ──────────────────────────────────────────────────

  Future<bool> completeSsoLogin({
    required String homeserver,
    required String loginToken,
  }) async {
    final success = await auth.completeSsoLogin(
      homeserver: homeserver,
      loginToken: loginToken,
    );
    if (success) {
      try {
        await sync.startSync(timeout: const Duration(minutes: 5));
        await auth.saveSessionBackup();
      } catch (e) {
        debugPrint('[Kohera] Post-login sync error: $e');
      }
    }
    return success;
  }

  // ── Registration ──────────────────────────────────────────────

  Future<void> completeRegistration(
    RegisterResponse response, {
    String? password,
  }) async {
    if (password != null) uia.setCachedPassword(password);
    await auth.completeRegistration(response, password: password);
    try {
      await sync.startSync(timeout: const Duration(minutes: 5));
      await auth.saveSessionBackup();
    } catch (e) {
      debugPrint('[Kohera] Post-login sync error: $e');
    }
  }

  // ── Logout ────────────────────────────────────────────────────

  Future<void> logout() async {
    await auth.logout();
    await chatBackup.deleteStoredRecoveryKey();
  }

  // ── Soft Logout ──────────────────────────────────────────────

  Future<void> handleSoftLogout() async {
    debugPrint('[Kohera] Soft logout detected, attempting token refresh...');
    try {
      await _client.refreshAccessToken();
      await auth.persistCredentials();
      await auth.saveSessionBackup();
      debugPrint('[Kohera] Token refreshed successfully');
    } catch (e) {
      debugPrint('[Kohera] Token refresh failed: $e');
      await auth.logout();
      await chatBackup.deleteStoredRecoveryKey();
    }
  }

  // ── Private: Auth Observer ──────────────────────────────────────

  void _onAuthChanged() {
    if (auth.isLoggedIn) {
      uia.listenForUia();
      _listenForLoginState();
      unawaited(callPushRuleManager.ensureRule());
    } else {
      unawaited(_loginStateSub?.cancel());
      _loginStateSub = null;
      sync.cancelSyncSub();
      uia.clearCachedPassword();
      uia.cancelUiaSub();
      selection.resetSelection();
      chatBackup.resetChatBackupState();
      _hasSkippedSetup = false;
    }
    notifyListeners();
  }

  // ── Private: Login State Stream ─────────────────────────────────

  void _listenForLoginState() {
    if (_loginStateSub != null) return;
    _loginStateSub = _client.onLoginStateChanged.stream.listen((state) async {
      if (state == LoginState.loggedOut && auth.isLoggedIn) {
        debugPrint('[Kohera] Server-side logout detected');
        await auth.handleServerLogout();
        await chatBackup.deleteStoredRecoveryKey();
      }
    });
  }

  // ── Private: Initialization ─────────────────────────────────────

  Future<void> _activateSession() async {
    auth.activateRestoredSession();
    unawaited(
      sync.startSync().catchError((Object e) {
        if (e is! TimeoutException) {
          debugPrint('[Kohera] Background sync error: $e');
        }
      }),
    );
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
      _storage.read(key: koheraKey(clientName, 'access_token')),
      _storage.read(key: koheraKey(clientName, 'refresh_token')),
      _storage.read(key: koheraKey(clientName, 'user_id')),
      _storage.read(key: koheraKey(clientName, 'homeserver')),
      _storage.read(key: koheraKey(clientName, 'device_id')),
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
      debugPrint('[Kohera] Failed to read session keys: $e');
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
        '[Kohera] Restoring session for ${keys.userId} on ${keys.homeserver} '
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
        newDeviceName: 'Kohera Flutter',
        newOlmAccount: backup?.olmAccount,
      );
      debugPrint('[Kohera] Session restored – '
          'encryption=${_client.encryption != null ? "available" : "null"}, '
          'encryptionEnabled=${_client.encryptionEnabled}');
      await _activateSession();
      try {
        await auth.saveSessionBackup();
      } catch (e) {
        debugPrint('[Kohera] saveSessionBackup after restore failed '
            '(non-fatal): $e');
      }
      return;
    } catch (e, s) {
      debugPrint('[Kohera] Session restore failed: $e');
      debugPrint('[Kohera] Stack trace:\n$s');

      final cause = _unwrapInitException(e);

      if (_isExpiredTokenError(cause)) {
        final refreshed = await _tryDatabaseRestore();
        if (refreshed) return;
      }

      auth.isLoggedIn = false;
      if (auth.isPermanentAuthFailure(cause)) {
        await _clearSessionAndBackup();
      }
    }
  }

  Future<bool> _tryDatabaseRestore() async {
    debugPrint('[Kohera] Attempting database-only restore (token refresh)...');
    try {
      await _client.init();
      if (_client.isLogged()) {
        await _activateSession();
        try {
          if (_client.accessToken != null) {
            await auth.persistCredentials();
          }
          await auth.saveSessionBackup();
        } catch (e) {
          debugPrint('[Kohera] Persisting restored session failed '
              '(non-fatal): $e');
        }
        debugPrint('[Kohera] Session restored via database token refresh');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Kohera] Database-only restore failed: $e');
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

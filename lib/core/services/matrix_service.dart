import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lattice/core/services/client_manager.dart' show ClientManager;
import 'package:lattice/core/services/mixins/auth_mixin.dart';
import 'package:lattice/core/services/mixins/chat_backup_mixin.dart';
import 'package:lattice/core/services/mixins/selection_mixin.dart';
import 'package:lattice/core/services/mixins/sync_mixin.dart';
import 'package:lattice/core/services/mixins/uia_mixin.dart';
import 'package:lattice/core/services/session_backup.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports, no public API for ClientInitException
import 'package:matrix/src/utils/client_init_exception.dart';

/// Storage key helper shared across mixins.
String latticeKey(String clientName, String suffix) =>
    'lattice_${clientName}_$suffix';

/// Central service that owns the [Client] instance and exposes
/// reactive state to the widget tree via [ChangeNotifier].
class MatrixService extends ChangeNotifier
    with SelectionMixin, ChatBackupMixin, UiaMixin, SyncMixin, AuthMixin {
  /// Maps common network exceptions to user-friendly error messages.
  static String friendlyAuthError(Object e) {
    if (e is SocketException) return 'Could not reach server';
    if (e is TimeoutException) return 'Connection timed out';
    if (e is FormatException) return 'Invalid server response';
    return e.toString();
  }

  MatrixService({
    required Client client,
    FlutterSecureStorage? storage,
    this.clientName = 'default',
  })  : _client = client,
        _storage = storage ?? const FlutterSecureStorage();

  // ── Fields ──────────────────────────────────────────────────────

  final FlutterSecureStorage _storage;

  @override
  final String clientName;

  final Client _client;
  @override
  Client get client => _client;

  @override
  FlutterSecureStorage get storage => _storage;

  bool _isLoggedIn = false;
  @override
  bool get isLoggedIn => _isLoggedIn;

  @protected
  @override
  set isLoggedIn(bool value) => _isLoggedIn = value;

  @override
  String Function(Object e) get friendlyError => friendlyAuthError;

  /// Sets the logged-in state directly. Only for testing.
  @visibleForTesting
  set isLoggedInForTest(bool value) => _isLoggedIn = value;

  bool _disposed = false;

  /// Whether this service has been disposed.
  bool get disposed => _disposed;

  // ── Public API ──────────────────────────────────────────────────

  /// Initializes the service, optionally restoring a saved session.
  ///
  /// When [restoreSession] is true (default), migrates storage keys and
  /// attempts to restore a session from secure storage. When false, only
  /// skips restore (used by [ClientManager] for login flows).
  Future<void> init({bool restoreSession = true}) async {
    if (restoreSession) await migrateStorageKeys();
    if (restoreSession) {
      await _restoreSession();
      notifyListeners();
    }
  }

  @override
  Future<void> saveSessionBackup() async {
    final backup = SessionBackup(
      accessToken: _client.accessToken!,
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
    cancelSyncSub();
    cancelUiaSub();
    cancelLoginStateSub();
    disposeUiaController();
    super.dispose();
  }

  // ── Private: Initialization ─────────────────────────────────────

  /// Wires up listeners and starts syncing after a successful session restore.
  ///
  /// A sync timeout is not treated as a session failure — the SDK client is
  /// already initialized and the background sync loop will keep running.
  Future<void> _activateSession() async {
    listenForUia();
    listenForLoginState();
    _isLoggedIn = true;
    try {
      await startSync();
    } on TimeoutException {
      debugPrint('[Lattice] Initial sync timed out during session restore – '
          'continuing in background');
    }
  }

  // ── Private: Session Keys ──────────────────────────────────────

  /// Clears both the stored session keys and the session backup.
  Future<void> _clearSessionAndBackup() async {
    await clearSessionKeys();
    await SessionBackup.delete(clientName: clientName, storage: _storage);
  }

  /// Reads stored session credentials from secure storage.
  Future<
      ({
        String? token,
        String? userId,
        String? homeserver,
        String? deviceId
      })> _readSessionKeys() async {
    final results = await Future.wait([
      _storage.read(key: latticeKey(clientName, 'access_token')),
      _storage.read(key: latticeKey(clientName, 'user_id')),
      _storage.read(key: latticeKey(clientName, 'homeserver')),
      _storage.read(key: latticeKey(clientName, 'device_id')),
    ]);
    return (
      token: results[0],
      userId: results[1],
      homeserver: results[2],
      deviceId: results[3],
    );
  }

  // ── Private: Session Restore ───────────────────────────────────

  /// Attempts to restore a session from secure storage.
  ///
  /// The strategy is to make one well-prepared [Client.init] call with
  /// the best available data. The session backup's OLM account is always
  /// included (when available) because the SDK database copy can become
  /// stale after an unclean shutdown. A failed [Client.init] calls
  /// [Client.clear] internally which wipes the SDK database, so retrying
  /// init on the same client is unreliable and avoided here.
  ///
  /// The one exception is expired tokens: the SDK database may contain a
  /// refresh token that [Client.init] (without credential overrides) can
  /// use to obtain a fresh access token automatically.
  Future<void> _restoreSession() async {
    final keys = await _readSessionKeys();

    if (keys.token == null ||
        keys.userId == null ||
        keys.homeserver == null) {
      return;
    }

    // Pre-load the session backup. Its pickled OLM account may be fresher
    // than the SDK database copy, which can become stale if the app is
    // killed before the database is flushed.
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

      // Unwrap ClientInitException — the SDK wraps the real error.
      final cause = _unwrapInitException(e);

      // Expired token: the SDK database may hold a refresh token. A bare
      // init() (no credential overrides) lets the SDK use it. This is the
      // only retry we attempt because the first failure already called
      // Client.clear() which wiped the database — providing credentials
      // again won't help since the OLM/device state is gone.
      if (_isExpiredTokenError(cause)) {
        final refreshed = await _tryDatabaseRestore();
        if (refreshed) return;
      }

      _isLoggedIn = false;
      if (isPermanentAuthFailure(cause)) {
        await _clearSessionAndBackup();
      }
    }
  }

  /// Tries to initialize the client from the SDK database without overriding
  /// the access token. The database may contain a refresh token that lets the
  /// SDK obtain a fresh access token automatically.
  Future<bool> _tryDatabaseRestore() async {
    debugPrint('[Lattice] Attempting database-only restore (token refresh)...');
    try {
      await _client.init();
      if (_client.isLogged()) {
        // Persist the refreshed token so future startups use it.
        if (_client.accessToken != null) {
          await _storage.write(
            key: latticeKey(clientName, 'access_token'),
            value: _client.accessToken,
          );
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

  /// Unwraps a [ClientInitException] to get the original error.
  /// The SDK wraps all init failures in this type, but our classifiers
  /// need the underlying [MatrixException].
  static Object _unwrapInitException(Object e) =>
      e is ClientInitException ? e.originalException : e;

  /// Whether the error is specifically an expired token (not revoked/unknown).
  static bool _isExpiredTokenError(Object e) {
    if (e is MatrixException && e.errcode == 'M_UNKNOWN_TOKEN') {
      return e.errorMessage.toLowerCase().contains('expired');
    }
    return false;
  }

}

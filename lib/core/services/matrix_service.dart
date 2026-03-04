import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqflite_native;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'session_backup.dart';
import 'mixins/selection_mixin.dart';
import 'mixins/chat_backup_mixin.dart';
import 'mixins/uia_mixin.dart';
import 'mixins/sync_mixin.dart';
import 'mixins/auth_mixin.dart';

/// Storage key helper shared across mixins.
String latticeKey(String clientName, String suffix) =>
    'lattice_${clientName}_$suffix';

/// Factory function that creates a configured [Client] instance.
typedef ClientFactory = Future<Client> Function(
  String clientName, {
  Future<void> Function(Client)? onSoftLogout,
});

/// Default production factory: sets up sqflite DB and constructs [Client].
Future<Client> createDefaultClient(
  String clientName, {
  Future<void> Function(Client)? onSoftLogout,
}) async {
  final Database sqfliteDb;
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'lattice_$clientName.db');
    sqfliteDb = await sqflite_native.openDatabase(dbPath);
  } else {
    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'lattice_$clientName.db');
    sqfliteDb = await dbFactory.openDatabase(dbPath);
  }
  final database = await MatrixSdkDatabase.init(
    'lattice_$clientName',
    database: sqfliteDb,
  );
  return Client(
    'Lattice ($clientName)',
    database: database,
    logLevel: kReleaseMode ? Level.warning : Level.verbose,
    defaultNetworkRequestTimeout: const Duration(minutes: 2),
    onSoftLogout: onSoftLogout,
    verificationMethods: {
      KeyVerificationMethod.emoji,
      KeyVerificationMethod.numbers,
    },
    nativeImplementations: NativeImplementationsIsolate(
      compute,
      vodozemacInit: () => vod.init(),
    ),
  );
}

/// An SSO identity provider advertised by the homeserver.
class SsoIdentityProvider {
  final String id;
  final String name;
  final String? icon;

  const SsoIdentityProvider({
    required this.id,
    required this.name,
    this.icon,
  });
}

/// Describes what authentication methods a homeserver supports.
class ServerAuthCapabilities {
  final bool supportsPassword;
  final bool supportsSso;
  final bool supportsRegistration;
  final List<SsoIdentityProvider> ssoIdentityProviders;
  final List<String> registrationStages;

  /// The resolved homeserver URI after .well-known lookup.
  final Uri? resolvedHomeserver;

  const ServerAuthCapabilities({
    this.supportsPassword = false,
    this.supportsSso = false,
    this.supportsRegistration = false,
    this.ssoIdentityProviders = const [],
    this.registrationStages = const [],
    this.resolvedHomeserver,
  });
}

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
    Client? client,
    FlutterSecureStorage? storage,
    this.clientName = 'default',
    ClientFactory? clientFactory,
  })  : _injectedClient = client,
        _clientFactory = clientFactory ?? createDefaultClient,
        _storage = storage ?? const FlutterSecureStorage() {
    if (client != null) {
      _client = client;
    }
  }

  final Client? _injectedClient;
  final ClientFactory _clientFactory;
  final FlutterSecureStorage _storage;
  @override
  final String clientName;

  late Client _client;
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

  // ── Initialization ───────────────────────────────────────────

  /// Creates a fresh [Client] via the factory with soft-logout wired up.
  Future<Client> _newClient() => _clientFactory(
        clientName,
        onSoftLogout: (_) async => handleSoftLogout(),
      );

  /// Initializes the client, optionally restoring a saved session.
  ///
  /// When [restoreSession] is true (default), migrates storage keys and
  /// attempts to restore a session from secure storage. When false, only
  /// creates the client instance (used by [ClientManager] for login flows).
  Future<void> init({bool restoreSession = true}) async {
    if (_injectedClient != null) {
      _client = _injectedClient!;
      return;
    }

    if (restoreSession) await migrateStorageKeys();
    _client = await _newClient();
    if (restoreSession) {
      await _restoreSession();
      notifyListeners();
    }
  }

  // ── Session Activation ─────────────────────────────────────────

  /// Wires up listeners and starts syncing after a successful session restore.
  Future<void> _activateSession() async {
    listenForUia();
    listenForLoginState();
    _isLoggedIn = true;
    await startSync();
  }

  /// Activates the session and persists a session backup.
  Future<void> _completeRestore() async {
    await _activateSession();
    await saveSessionBackup();
  }

  // ── Session Keys ───────────────────────────────────────────────

  /// Clears both the stored session keys and the session backup.
  Future<void> _clearSessionAndBackup() async {
    await clearSessionKeys();
    await SessionBackup.delete(clientName: clientName, storage: _storage);
  }

  /// Writes session credentials to secure storage.
  Future<void> _persistSessionKeys({
    required String token,
    required String userId,
    required String homeserver,
    String? deviceId,
  }) =>
      Future.wait([
        _storage.write(
            key: latticeKey(clientName, 'access_token'), value: token),
        _storage.write(key: latticeKey(clientName, 'user_id'), value: userId),
        _storage.write(
            key: latticeKey(clientName, 'homeserver'), value: homeserver),
        if (deviceId != null)
          _storage.write(
              key: latticeKey(clientName, 'device_id'), value: deviceId),
      ]);

  /// Reads stored session credentials from secure storage.
  Future<({String? token, String? userId, String? homeserver, String? deviceId})>
      _readSessionKeys() async {
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

  // ── Session Restore ────────────────────────────────────────────

  /// Attempts to restore a session from secure storage, falling back to
  /// backup restore or device re-registration on failure.
  Future<void> _restoreSession() async {
    try {
      final keys = await _readSessionKeys();

      if (keys.token != null &&
          keys.userId != null &&
          keys.homeserver != null) {
        debugPrint(
            '[Lattice] Restoring session for ${keys.userId} on ${keys.homeserver} '
            '(deviceId=${keys.deviceId}, clientName=$clientName)');
        final homeserverUri = Uri.parse(keys.homeserver!);
        _client.homeserver = homeserverUri;
        await _client.init(
          newToken: keys.token,
          newUserID: keys.userId,
          newDeviceID: keys.deviceId,
          newHomeserver: homeserverUri,
          newDeviceName: 'Lattice Flutter',
        );
        debugPrint('[Lattice] Session restored – '
            'encryption=${_client.encryption != null ? "available" : "null"}, '
            'encryptionEnabled=${_client.encryptionEnabled}');
        await _completeRestore();
      }
    } catch (e, s) {
      debugPrint('[Lattice] Session restore failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');

      // The SDK client may be stuck in a partially initialized state after
      // the failed _client.init() call. Dispose and recreate before any
      // further restore attempts so we get a clean instance.
      await recreateClient();

      // If the token expired, try initializing from the SDK database alone.
      // The database may contain a refresh token that lets the SDK obtain a
      // new access token automatically without overriding with the stale one.
      if (_isExpiredTokenError(e)) {
        final refreshed = await _tryDatabaseRestore();
        if (refreshed) return;
      }

      // Try restoring from session backup before giving up.
      final restored = await _restoreFromBackup();
      if (!restored) {
        _isLoggedIn = false;
        if (isPermanentAuthFailure(e)) {
          await _clearSessionAndBackup();
        } else if (_isOlmKeyUploadFailure(e)) {
          // The local OLM account was lost (e.g. DB deleted) but the
          // device ID still references server-side keys we can no longer
          // match. Clear the device ID so the SDK registers a fresh
          // device on the next init attempt.
          debugPrint('[Lattice] Clearing stale device ID and retrying init');
          await _storage.delete(key: latticeKey(clientName, 'device_id'));
          await _retryInitWithoutDevice();
        }
      }
    }
  }

  // ── Session Backup ────────────────────────────────────────────

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

  Future<bool> _restoreFromBackup() async {
    debugPrint('[Lattice] Attempting restore from session backup...');
    try {
      final backup = await SessionBackup.load(
        clientName: clientName,
        storage: _storage,
      );
      if (backup == null) {
        debugPrint('[Lattice] No session backup found');
        return false;
      }

      final homeserverUri = Uri.parse(backup.homeserver);
      _client.homeserver = homeserverUri;
      await _client.init(
        newToken: backup.accessToken,
        newUserID: backup.userId,
        newDeviceID: backup.deviceId,
        newHomeserver: homeserverUri,
        newDeviceName: backup.deviceName ?? 'Lattice Flutter',
        newOlmAccount: backup.olmAccount,
      );

      // Update stored session keys from backup.
      await _persistSessionKeys(
        token: backup.accessToken,
        userId: backup.userId,
        homeserver: backup.homeserver,
        deviceId: backup.deviceId,
      );

      await _activateSession();
      debugPrint('[Lattice] Session restored from backup');
      return true;
    } catch (e, s) {
      debugPrint('[Lattice] Restore from backup also failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      if (isPermanentAuthFailure(e)) {
        await _clearSessionAndBackup();
      }
      return false;
    }
  }

  /// Whether the error is specifically an expired token (not revoked/unknown).
  static bool _isExpiredTokenError(Object e) {
    if (e is MatrixException && e.errcode == 'M_UNKNOWN_TOKEN') {
      return e.errorMessage.toLowerCase().contains('expired');
    }
    return false;
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
        await _completeRestore();
        debugPrint('[Lattice] Session restored via database token refresh');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Lattice] Database-only restore failed: $e');
      // Recreate client again since it may be in a bad state.
      await recreateClient();
      return false;
    }
  }

  /// Whether the error indicates a failed OLM key upload, typically caused by
  /// a lost local OLM account while the device ID still references server-side
  /// keys. Checks both the Matrix SDK error and common message patterns.
  static bool _isOlmKeyUploadFailure(Object e) {
    if (e is MatrixException && e.errcode == 'M_UNKNOWN') {
      return e.errorMessage.contains('key upload');
    }
    // Fallback: the SDK may wrap the error in a generic exception.
    final msg = '$e';
    return msg.contains('Upload key failed') ||
        msg.contains('one_time_key_counts');
  }

  /// Re-attempt session restore without a device ID so the SDK registers a
  /// fresh device. Called when the local OLM account was lost and the old
  /// device's keys can no longer be uploaded.
  ///
  /// Assumes the caller has already disposed and recreated [_client] so we
  /// get a clean SDK instance (see [_restoreSession]).
  Future<void> _retryInitWithoutDevice() async {
    assert(_client.userID == null,
        '_retryInitWithoutDevice requires a fresh client');
    try {
      final keys = await _readSessionKeys();

      if (keys.token == null ||
          keys.userId == null ||
          keys.homeserver == null) {
        return;
      }

      final homeserverUri = Uri.parse(keys.homeserver!);
      _client.homeserver = homeserverUri;
      await _client.init(
        newToken: keys.token,
        newUserID: keys.userId,
        newHomeserver: homeserverUri,
        newDeviceName: 'Lattice Flutter',
      );

      // Persist the new device ID assigned by the server.
      if (_client.deviceID != null) {
        await _storage.write(
            key: latticeKey(clientName, 'device_id'), value: _client.deviceID);
      }

      await _completeRestore();
      debugPrint('[Lattice] Session restored with new device ID '
          '${_client.deviceID}');
    } catch (e, s) {
      debugPrint('[Lattice] Retry without device ID also failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      _isLoggedIn = false;
    }
  }

  bool _disposed = false;

  /// Disposes the current [Client] and creates a fresh instance so that
  /// a subsequent [login] call gets a clean SDK client.
  @override
  Future<void> recreateClient() async {
    _client.dispose();
    _client = await _newClient();
  }

  /// Whether this service has been disposed.
  bool get disposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    _isLoggedIn = false;
    cancelSyncSub();
    cancelUiaSub();
    cancelLoginStateSub();
    disposeUiaController();
    _client.dispose();
    super.dispose();
  }
}

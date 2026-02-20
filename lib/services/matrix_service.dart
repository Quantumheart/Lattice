import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
  MatrixService({
    Client? client,
    FlutterSecureStorage? storage,
    this.clientName = 'default',
  })  : _injectedClient = client,
        _storage = storage ?? const FlutterSecureStorage() {
    if (client != null) {
      _client = client;
    }
  }

  final Client? _injectedClient;
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

  /// Sets the logged-in state directly. Only for testing.
  @visibleForTesting
  set isLoggedInForTest(bool value) => _isLoggedIn = value;

  // ── Initialization ───────────────────────────────────────────

  /// Initializes the client, creating the database and restoring the session.
  /// Called by [ClientManager]; not called automatically from the constructor.
  Future<void> init() async {
    if (_injectedClient != null) {
      _client = _injectedClient!;
      return;
    }

    await migrateStorageKeys();

    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'lattice_$clientName.db');
    final sqfliteDb = await dbFactory.openDatabase(dbPath);
    final database = await MatrixSdkDatabase.init(
      'lattice_$clientName',
      database: sqfliteDb,
    );
    _client = Client(
      'Lattice ($clientName)',
      database: database,
      logLevel: kReleaseMode ? Level.warning : Level.verbose,
      defaultNetworkRequestTimeout: const Duration(minutes: 2),
      onSoftLogout: (_) => handleSoftLogout(),
      verificationMethods: {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers,
      },
      nativeImplementations: NativeImplementationsIsolate(
        compute,
        vodozemacInit: () => vod.init(),
      ),
    );

    // Attempt to restore session from secure storage.
    try {
      final token =
          await _storage.read(key: latticeKey(clientName, 'access_token'));
      final userId =
          await _storage.read(key: latticeKey(clientName, 'user_id'));
      final homeserver =
          await _storage.read(key: latticeKey(clientName, 'homeserver'));
      final deviceId =
          await _storage.read(key: latticeKey(clientName, 'device_id'));

      if (token != null && userId != null && homeserver != null) {
        debugPrint('[Lattice] Restoring session for $userId on $homeserver '
            '(deviceId=$deviceId, clientName=$clientName)');
        final homeserverUri = Uri.parse(homeserver);
        _client.homeserver = homeserverUri;
        await _client.init(
          newToken: token,
          newUserID: userId,
          newDeviceID: deviceId,
          newHomeserver: homeserverUri,
          newDeviceName: 'Lattice Flutter',
        );
        debugPrint('[Lattice] Session restored – '
            'encryption=${_client.encryption != null ? "available" : "null"}, '
            'encryptionEnabled=${_client.encryptionEnabled}');
        listenForUia();
        listenForLoginState();
        await startSync();
        _isLoggedIn = true;

        // Write session backup after successful restore + first sync.
        await saveSessionBackup();
      }
    } catch (e, s) {
      debugPrint('[Lattice] Session restore failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');

      // Try restoring from session backup before giving up.
      final restored = await _restoreFromBackup();
      if (!restored) {
        _isLoggedIn = false;
        if (isPermanentAuthFailure(e)) {
          await clearSessionKeys();
          await SessionBackup.delete(
            clientName: clientName,
            storage: _storage,
          );
        } else if ('$e'.contains('Upload key failed')) {
          // The local OLM account was lost (e.g. DB deleted) but the
          // device ID still references server-side keys we can no longer
          // match. Clear the device ID so the SDK registers a fresh
          // device on the next init attempt.
          debugPrint('[Lattice] Clearing stale device ID and retrying init');
          await _storage.delete(
              key: latticeKey(clientName, 'device_id'));
          await _retryInitWithoutDevice();
        }
      }
    }
    notifyListeners();
  }

  /// Creates the client instance without restoring a session.
  /// Used by [ClientManager] for the login flow.
  Future<void> initClient() async {
    if (_injectedClient != null) {
      _client = _injectedClient!;
      return;
    }

    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'lattice_$clientName.db');
    final sqfliteDb = await dbFactory.openDatabase(dbPath);
    final database = await MatrixSdkDatabase.init(
      'lattice_$clientName',
      database: sqfliteDb,
    );
    _client = Client(
      'Lattice ($clientName)',
      database: database,
      logLevel: kReleaseMode ? Level.warning : Level.verbose,
      defaultNetworkRequestTimeout: const Duration(minutes: 2),
      onSoftLogout: (_) => handleSoftLogout(),
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
      await _storage.write(
          key: latticeKey(clientName, 'access_token'),
          value: backup.accessToken);
      await _storage.write(
          key: latticeKey(clientName, 'user_id'), value: backup.userId);
      await _storage.write(
          key: latticeKey(clientName, 'homeserver'), value: backup.homeserver);
      await _storage.write(
          key: latticeKey(clientName, 'device_id'), value: backup.deviceId);

      listenForUia();
      listenForLoginState();
      await startSync();
      _isLoggedIn = true;
      debugPrint('[Lattice] Session restored from backup');
      return true;
    } catch (e, s) {
      debugPrint('[Lattice] Restore from backup also failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      if (isPermanentAuthFailure(e)) {
        await clearSessionKeys();
        await SessionBackup.delete(
          clientName: clientName,
          storage: _storage,
        );
      }
      return false;
    }
  }

  /// Re-attempt session restore without a device ID so the SDK registers a
  /// fresh device. Called when the local OLM account was lost and the old
  /// device's keys can no longer be uploaded.
  Future<void> _retryInitWithoutDevice() async {
    try {
      final token =
          await _storage.read(key: latticeKey(clientName, 'access_token'));
      final userId =
          await _storage.read(key: latticeKey(clientName, 'user_id'));
      final homeserver =
          await _storage.read(key: latticeKey(clientName, 'homeserver'));

      if (token == null || userId == null || homeserver == null) return;

      final homeserverUri = Uri.parse(homeserver);
      _client.homeserver = homeserverUri;
      await _client.init(
        newToken: token,
        newUserID: userId,
        newHomeserver: homeserverUri,
        newDeviceName: 'Lattice Flutter',
      );

      // Persist the new device ID assigned by the server.
      if (_client.deviceID != null) {
        await _storage.write(
            key: latticeKey(clientName, 'device_id'),
            value: _client.deviceID);
      }

      listenForUia();
      listenForLoginState();
      await startSync();
      _isLoggedIn = true;
      await saveSessionBackup();
      debugPrint('[Lattice] Session restored with new device ID '
          '${_client.deviceID}');
    } catch (e, s) {
      debugPrint('[Lattice] Retry without device ID also failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      _isLoggedIn = false;
    }
  }

  @override
  void dispose() {
    cancelSyncSub();
    cancelUiaSub();
    cancelLoginStateSub();
    disposeUiaController();
    _client.dispose();
    super.dispose();
  }
}

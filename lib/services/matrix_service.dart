import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Central service that owns the [Client] instance and exposes
/// reactive state to the widget tree via [ChangeNotifier].
class MatrixService extends ChangeNotifier {
  MatrixService({
    Client? client,
    FlutterSecureStorage? storage,
  })  : _injectedClient = client,
        _storage = storage ?? const FlutterSecureStorage() {
    if (client != null) {
      _client = client;
    } else {
      init();
    }
  }

  final Client? _injectedClient;
  final FlutterSecureStorage _storage;

  late Client _client;
  Client get client => _client;

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  bool _syncing = false;
  bool get syncing => _syncing;

  String? _loginError;
  String? get loginError => _loginError;

  // ── Currently selected space & room ──────────────────────────
  String? _selectedSpaceId;
  String? get selectedSpaceId => _selectedSpaceId;

  String? _selectedRoomId;
  String? get selectedRoomId => _selectedRoomId;

  Room? get selectedRoom =>
      _selectedRoomId != null ? _client.getRoomById(_selectedRoomId!) : null;

  // ── Sync subscription ──────────────────────────────────────────
  StreamSubscription? _syncSub;
  StreamSubscription? _firstSyncSub;
  StreamSubscription? _uiaSub;

  // ── UIA (User-Interactive Authentication) ──────────────────────
  String? _cachedPassword;

  /// Expose UIA requests that need user interaction (e.g. password prompt).
  /// The UI should listen to this and call [completeUiaWithPassword].
  final _uiaController = StreamController<UiaRequest>.broadcast();
  Stream<UiaRequest> get onUiaRequest => _uiaController.stream;

  // ── Initialization ───────────────────────────────────────────
  Future<void> init() async {
    if (_injectedClient != null) return;

    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'lattice.db');
    final sqfliteDb = await dbFactory.openDatabase(dbPath);
    final database = await MatrixSdkDatabase.init(
      'lattice',
      database: sqfliteDb,
    );
    _client = Client(
      'Lattice',
      database: database,
      logLevel: kReleaseMode ? Level.warning : Level.verbose,
      defaultNetworkRequestTimeout: const Duration(minutes: 2),
      nativeImplementations: NativeImplementationsIsolate(
        compute,
        vodozemacInit: () => vod.init(),
      ),
    );

    // Attempt to restore session from secure storage.
    try {
      final token = await _storage.read(key: 'lattice_access_token');
      final userId = await _storage.read(key: 'lattice_user_id');
      final homeserver = await _storage.read(key: 'lattice_homeserver');
      final deviceId = await _storage.read(key: 'lattice_device_id');

      if (token != null && userId != null && homeserver != null) {
        debugPrint('[Lattice] Restoring session for $userId on $homeserver '
            '(deviceId=$deviceId)');
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
        _isLoggedIn = true;
        _listenForUia();
        _startSync();
      }
    } catch (e, s) {
      debugPrint('[Lattice] Session restore failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      _isLoggedIn = false;
      await _clearSessionKeys();
    }
    notifyListeners();
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
      _client.homeserver = Uri.parse(hs);
      await _client.checkHomeserver(Uri.parse(hs));
      debugPrint('[Lattice] Homeserver OK');

      debugPrint('[Lattice] Logging in as $username ...');
      await _client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username.trim()),
        password: password,
        initialDeviceDisplayName: 'Lattice Flutter',
      );
      debugPrint('[Lattice] Login complete – '
          'deviceId=${_client.deviceID}, '
          'userId=${_client.userID}, '
          'encryption=${_client.encryption != null ? "available" : "null"}, '
          'encryptionEnabled=${_client.encryptionEnabled}');

      // Persist credentials.
      await _storage.write(
          key: 'lattice_access_token', value: _client.accessToken);
      await _storage.write(key: 'lattice_user_id', value: _client.userID);
      await _storage.write(
          key: 'lattice_homeserver', value: _client.homeserver.toString());
      await _storage.write(key: 'lattice_device_id', value: _client.deviceID);

      _cachedPassword = password;
      _isLoggedIn = true;
      _listenForUia();
      _startSync();
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

  // ── Logout ───────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      if (_client.homeserver != null && _client.accessToken != null) {
        await _client.logout();
      }
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    await _clearSessionKeys();
    _isLoggedIn = false;
    _cachedPassword = null;
    _uiaSub?.cancel();
    _selectedSpaceId = null;
    _selectedRoomId = null;
    _chatBackupNeeded = null;
    notifyListeners();
  }

  // ── UIA Handler ──────────────────────────────────────────────
  void _listenForUia() {
    _uiaSub?.cancel();
    _uiaSub = _client.onUiaRequest.stream.listen(_handleUiaRequest);
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
        final userId = _client.userID;
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
    final userId = _client.userID;
    if (userId == null) return;
    request.completeStage(
      AuthenticationPassword(
        session: request.session,
        password: password,
        identifier: AuthenticationUserIdentifier(user: userId),
      ),
    );
  }

  /// Clear the cached login password from memory.
  /// Should be called after bootstrap completes to minimize exposure.
  void clearCachedPassword() {
    _cachedPassword = null;
  }

  // ── Sync ─────────────────────────────────────────────────────
  void _startSync() {
    _syncing = true;
    notifyListeners();
    _syncSub?.cancel();
    _syncSub = _client.onSync.stream.listen((_) {
      notifyListeners();
    });
    _firstSyncSub?.cancel();
    _firstSyncSub = _client.onSync.stream.first.asStream().listen((_) async {
      if (_isLoggedIn) {
        await checkChatBackupStatus();
      }
    });
  }

  // ── Session Key Management ────────────────────────────────────
  Future<void> _clearSessionKeys() async {
    await _storage.delete(key: 'lattice_access_token');
    await _storage.delete(key: 'lattice_user_id');
    await _storage.delete(key: 'lattice_homeserver');
    await _storage.delete(key: 'lattice_device_id');
    await _storage.delete(key: 'lattice_olm_account');
  }

  // ── Selection ────────────────────────────────────────────────
  void selectSpace(String? spaceId) {
    _selectedSpaceId = spaceId;
    notifyListeners();
  }

  void selectRoom(String? roomId) {
    _selectedRoomId = roomId;
    notifyListeners();
  }

  // ── Chat Backup ─────────────────────────────────────────────
  /// null = loading/unknown, true = needs setup, false = ok
  bool? _chatBackupNeeded;
  bool? get chatBackupNeeded => _chatBackupNeeded;
  bool get chatBackupEnabled => _chatBackupNeeded == false;

  bool _chatBackupLoading = false;
  bool get chatBackupLoading => _chatBackupLoading;

  String? _chatBackupError;
  String? get chatBackupError => _chatBackupError;

  Future<void> checkChatBackupStatus() async {
    try {
      final encryption = _client.encryption;
      if (encryption == null) {
        debugPrint('[BackupStatus] encryption is null');
        _chatBackupNeeded = true;
        notifyListeners();
        return;
      }

      final crossSigningEnabled = encryption.crossSigning.enabled;
      final keyBackupEnabled = encryption.keyManager.enabled;

      if (!crossSigningEnabled || !keyBackupEnabled) {
        debugPrint('[BackupStatus] crossSigningEnabled=$crossSigningEnabled, '
            'keyBackupEnabled=$keyBackupEnabled');
        _chatBackupNeeded = true;
        notifyListeners();
        return;
      }

      final crossSigningCached = await encryption.crossSigning.isCached();
      final keyBackupCached = await encryption.keyManager.isCached();
      final isUnknown = _client.isUnknownSession;

      debugPrint('[BackupStatus] crossSigningCached=$crossSigningCached, '
          'keyBackupCached=$keyBackupCached, isUnknown=$isUnknown');
      _chatBackupNeeded = !crossSigningCached || !keyBackupCached || isUnknown;
      notifyListeners();
    } catch (e) {
      debugPrint('checkChatBackupStatus error: $e');
      _chatBackupNeeded = true;
      notifyListeners();
    }
  }

  // ── Recovery Key Storage ──────────────────────────────────────

  Future<String?> getStoredRecoveryKey() async {
    final userId = _client.userID;
    if (userId == null) return null;
    return _storage.read(key: 'ssss_recovery_key_$userId');
  }

  Future<void> storeRecoveryKey(String key) async {
    final userId = _client.userID;
    if (userId == null) return;
    await _storage.write(key: 'ssss_recovery_key_$userId', value: key);
  }

  Future<void> deleteStoredRecoveryKey() async {
    final userId = _client.userID;
    if (userId == null) return;
    await _storage.delete(key: 'ssss_recovery_key_$userId');
  }

  Future<void> disableChatBackup() async {
    _chatBackupError = null;
    _chatBackupLoading = true;
    notifyListeners();

    try {
      final encryption = _client.encryption;
      if (encryption == null) {
        throw Exception('Encryption is not available');
      }
      final info = await encryption.keyManager.getRoomKeysBackupInfo();
      await _client.deleteRoomKeysVersion(info.version);
      await deleteStoredRecoveryKey();
      _chatBackupNeeded = true;
    } catch (e) {
      debugPrint('disableChatBackup error: $e');
      _chatBackupError = 'Failed to disable chat backup. Please try again.';
    } finally {
      _chatBackupLoading = false;
      notifyListeners();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  /// Returns spaces (rooms with type m.space).
  List<Room> get spaces => _client.rooms
      .where((r) => r.isSpace)
      .toList()
    ..sort((a, b) => a.getLocalizedDisplayname().compareTo(b.getLocalizedDisplayname()));

  /// Returns non-space rooms, optionally filtered by current space.
  List<Room> get rooms {
    var list = _client.rooms.where((r) => !r.isSpace).toList();

    if (_selectedSpaceId != null) {
      final space = _client.getRoomById(_selectedSpaceId!);
      if (space != null) {
        final childIds = space.spaceChildren.map((c) => c.roomId).toSet();
        list = list.where((r) => childIds.contains(r.id)).toList();
      }
    }

    list.sort((a, b) {
      final aTs = a.lastEvent?.originServerTs ?? DateTime(1970);
      final bTs = b.lastEvent?.originServerTs ?? DateTime(1970);
      return bTs.compareTo(aTs);
    });

    return list;
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _firstSyncSub?.cancel();
    _uiaSub?.cancel();
    _uiaController.close();
    _client.dispose();
    super.dispose();
  }
}

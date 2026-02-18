import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    );

    // Attempt to restore session from secure storage.
    try {
      final token = await _storage.read(key: 'lattice_access_token');
      final userId = await _storage.read(key: 'lattice_user_id');
      final homeserver = await _storage.read(key: 'lattice_homeserver');
      final deviceId = await _storage.read(key: 'lattice_device_id');

      if (token != null && userId != null && homeserver != null) {
        _client.homeserver = Uri.parse(homeserver);
        await _client.init(
          newToken: token,
          newUserID: userId,
          newDeviceID: deviceId,
          newDeviceName: 'Lattice Flutter',
        );
        _isLoggedIn = true;
        _backupSessionState();
        _startSync();
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
      _isLoggedIn = false;
      // Clear session keys but preserve recovery key
      await _storage.delete(key: 'lattice_access_token');
      await _storage.delete(key: 'lattice_user_id');
      await _storage.delete(key: 'lattice_homeserver');
      await _storage.delete(key: 'lattice_device_id');
      await _storage.delete(key: 'lattice_olm_account');
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

      _client.homeserver = Uri.parse(hs);
      await _client.checkHomeserver(Uri.parse(hs));

      await _client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username.trim()),
        password: password,
        initialDeviceDisplayName: 'Lattice Flutter',
      );

      // Persist credentials.
      await _storage.write(
          key: 'lattice_access_token', value: _client.accessToken);
      await _storage.write(key: 'lattice_user_id', value: _client.userID);
      await _storage.write(
          key: 'lattice_homeserver', value: _client.homeserver.toString());
      await _storage.write(key: 'lattice_device_id', value: _client.deviceID);

      _isLoggedIn = true;
      _startSync();
      notifyListeners();
      return true;
    } catch (e) {
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
    } catch (_) {}
    await _storage.delete(key: 'lattice_access_token');
    await _storage.delete(key: 'lattice_user_id');
    await _storage.delete(key: 'lattice_homeserver');
    await _storage.delete(key: 'lattice_device_id');
    await _storage.delete(key: 'lattice_olm_account');
    _isLoggedIn = false;
    _selectedSpaceId = null;
    _selectedRoomId = null;
    _chatBackupNeeded = null;
    notifyListeners();
  }

  // ── Sync ─────────────────────────────────────────────────────
  void _startSync() {
    _syncing = true;
    notifyListeners();
    _client.onSync.stream.listen((_) {
      notifyListeners();
    });
    _client.onSync.stream.first.then((_) async {
      await checkChatBackupStatus();
    });
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
    final encryption = _client.encryption;
    if (encryption == null) {
      _chatBackupNeeded = true;
      notifyListeners();
      return;
    }

    final crossSigningEnabled = encryption.crossSigning.enabled;
    final keyBackupEnabled = encryption.keyManager.enabled;

    if (!crossSigningEnabled || !keyBackupEnabled) {
      _chatBackupNeeded = true;
      notifyListeners();
      return;
    }

    final crossSigningCached = await encryption.crossSigning.isCached();
    final keyBackupCached = await encryption.keyManager.isCached();
    final isUnknown = _client.isUnknownSession;

    _chatBackupNeeded = !crossSigningCached || !keyBackupCached || isUnknown;
    notifyListeners();
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
      _chatBackupError = e.toString();
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
    _client.dispose();
    super.dispose();
  }
}

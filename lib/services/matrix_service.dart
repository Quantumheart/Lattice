import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Central service that owns the [Client] instance and exposes
/// reactive state to the widget tree via [ChangeNotifier].
class MatrixService extends ChangeNotifier {
  MatrixService() {
    _init();
  }

  late final Client _client;
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
  Future<void> _init() async {
    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'helix_matrix.db');
    final sqfliteDb = await dbFactory.openDatabase(dbPath);
    final database = await MatrixSdkDatabase.init(
      'helix_matrix',
      database: sqfliteDb,
    );
    _client = Client(
      'HelixMatrix',
      database: database,
    );

    // Attempt to restore session from secure storage.
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'helix_access_token');
      final userId = await storage.read(key: 'helix_user_id');
      final homeserver = await storage.read(key: 'helix_homeserver');
      final deviceId = await storage.read(key: 'helix_device_id');

      if (token != null && userId != null && homeserver != null) {
        _client.homeserver = Uri.parse(homeserver);
        await _client.init(
          newToken: token,
          newUserID: userId,
          newDeviceID: deviceId,
          newDeviceName: 'Helix Flutter',
        );
        _isLoggedIn = true;
        _startSync();
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
      _isLoggedIn = false;
      const storage = FlutterSecureStorage();
      await storage.deleteAll();
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
        initialDeviceDisplayName: 'Helix Flutter',
      );

      // Persist credentials.
      const storage = FlutterSecureStorage();
      await storage.write(
          key: 'helix_access_token', value: _client.accessToken);
      await storage.write(key: 'helix_user_id', value: _client.userID);
      await storage.write(
          key: 'helix_homeserver', value: _client.homeserver.toString());
      await storage.write(key: 'helix_device_id', value: _client.deviceID);

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
      await _client.logout();
    } catch (_) {}
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    _isLoggedIn = false;
    _selectedSpaceId = null;
    _selectedRoomId = null;
    notifyListeners();
  }

  // ── Sync ─────────────────────────────────────────────────────
  void _startSync() {
    _syncing = true;
    notifyListeners();
    _client.onSync.stream.listen((_) {
      notifyListeners();
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

  // ── Helpers ──────────────────────────────────────────────────

  /// Returns spaces (rooms with type m.space).
  List<Room> get spaces => _client.rooms
      .where((r) => r.isSpace)
      .toList()
    ..sort((a, b) => a.displayname.compareTo(b.displayname));

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

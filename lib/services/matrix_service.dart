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
        _startSync();
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
      _isLoggedIn = false;
      await _storage.deleteAll();
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
      await _client.logout();
    } catch (_) {}
    await _storage.deleteAll();
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

  // ── Profile / Avatar ────────────────────────────────────────

  /// Fetches the logged-in user's profile from the homeserver.
  Future<Profile> fetchOwnProfile() async {
    return await _client.fetchOwnProfile();
  }

  /// Resolves an MXC URI to an HTTPS thumbnail URL.
  Future<Uri?> avatarThumbnailUrl(Uri? mxcUri, {int dimension = 128}) async {
    if (mxcUri == null) return null;
    return await mxcUri.getThumbnailUri(
      _client,
      width: dimension,
      height: dimension,
    );
  }

  /// Uploads [imageBytes] as the user's avatar and notifies listeners.
  Future<void> setAvatar(Uint8List imageBytes, {String? filename}) async {
    await _client.setAvatar(MatrixFile(
      bytes: imageBytes,
      name: filename ?? 'avatar.png',
    ));
    notifyListeners();
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }
}

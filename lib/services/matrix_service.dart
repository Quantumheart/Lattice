import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/encryption.dart';
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
    _client.onSync.stream.first.then((_) => checkChatBackupStatus());
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
  bool _chatBackupEnabled = false;
  bool get chatBackupEnabled => _chatBackupEnabled;

  bool _chatBackupLoading = false;
  bool get chatBackupLoading => _chatBackupLoading;

  String? _chatBackupError;
  String? get chatBackupError => _chatBackupError;

  void checkChatBackupStatus() {
    final encryption = _client.encryption;
    if (encryption == null) {
      _chatBackupEnabled = false;
    } else {
      _chatBackupEnabled =
          encryption.crossSigning.enabled && encryption.keyManager.enabled;
    }
    notifyListeners();
  }

  Future<String?> enableChatBackup() async {
    _chatBackupError = null;
    _chatBackupLoading = true;
    notifyListeners();

    final encryption = _client.encryption;
    if (encryption == null) {
      _chatBackupError = 'Encryption is not available';
      _chatBackupLoading = false;
      notifyListeners();
      return null;
    }

    final completer = Completer<String?>();

    try {
      encryption.bootstrap(onUpdate: (bootstrap) async {
        try {
          switch (bootstrap.state) {
            case BootstrapState.askWipeSsss:
              bootstrap.wipeSsss(true);
              break;
            case BootstrapState.askNewSsss:
              await bootstrap.newSsss();
              break;
            case BootstrapState.askUseExistingSsss:
              bootstrap.useExistingSsss(false);
              break;
            case BootstrapState.askBadSsss:
              bootstrap.ignoreBadSecrets(true);
              break;
            case BootstrapState.askWipeCrossSigning:
              await bootstrap.wipeCrossSigning(true);
              break;
            case BootstrapState.askSetupCrossSigning:
              await bootstrap.askSetupCrossSigning(
                setupMasterKey: true,
                setupSelfSigningKey: true,
                setupUserSigningKey: true,
              );
              break;
            case BootstrapState.askWipeOnlineKeyBackup:
              bootstrap.wipeOnlineKeyBackup(true);
              break;
            case BootstrapState.askSetupOnlineKeyBackup:
              await bootstrap.askSetupOnlineKeyBackup(true);
              break;
            case BootstrapState.done:
              if (!completer.isCompleted) {
                checkChatBackupStatus();
                completer.complete(bootstrap.newSsssKey?.recoveryKey);
              }
              break;
            case BootstrapState.error:
              if (!completer.isCompleted) {
                _chatBackupError = 'Bootstrap failed';
                completer.complete(null);
              }
              break;
            default:
              break;
          }
        } catch (e) {
          if (!completer.isCompleted) {
            _chatBackupError = e.toString();
            completer.complete(null);
          }
        }
      });
    } catch (e) {
      if (!completer.isCompleted) {
        _chatBackupError = e.toString();
        completer.complete(null);
      }
    }

    final result = await completer.future;
    _chatBackupLoading = false;
    notifyListeners();
    return result;
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
      _chatBackupEnabled = false;
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

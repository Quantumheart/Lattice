import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lattice/core/models/server_auth_capabilities.dart';
import 'package:lattice/core/models/space_node.dart';
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
    _uia = UiaService(client: _client);
    _chatBackup = ChatBackupService(
      client: _client,
      storage: _storage,
      onChanged: notifyListeners,
    );
    _selection = SelectionService(client: _client, onChanged: notifyListeners);
    _sync = SyncService(
      client: _client,
      onChanged: notifyListeners,
      onSyncEvent: () {
        _selection.invalidateSpaceTree();
        notifyListeners();
      },
      onPostSyncBackup: () async {
        await _chatBackup.checkChatBackupStatus();
        if (_chatBackup.chatBackupNeeded == true) {
          await _chatBackup.tryAutoUnlockBackup();
        }
      },
    );
    _auth = AuthService(
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

  late final UiaService _uia;
  late final ChatBackupService _chatBackup;
  late final SelectionService _selection;
  late final SyncService _sync;
  late final AuthService _auth;

  StreamSubscription<LoginState>? _loginStateSub;

  // ── UiaService delegates ────────────────────────────────────────

  Stream<UiaRequest<dynamic>> get onUiaRequest => _uia.onUiaRequest;
  void completeUiaWithPassword(UiaRequest<dynamic> request, String password) =>
      _uia.completeUiaWithPassword(request, password);
  void clearCachedPassword() => _uia.clearCachedPassword();

  // ── ChatBackupService delegates ─────────────────────────────────

  bool? get chatBackupNeeded => _chatBackup.chatBackupNeeded;
  bool get chatBackupEnabled => _chatBackup.chatBackupEnabled;
  bool get chatBackupLoading => _chatBackup.chatBackupLoading;
  String? get chatBackupError => _chatBackup.chatBackupError;
  Future<void> checkChatBackupStatus() => _chatBackup.checkChatBackupStatus();
  void requestMissingRoomKeys() => _chatBackup.requestMissingRoomKeys();
  Future<String?> getStoredRecoveryKey() => _chatBackup.getStoredRecoveryKey();
  Future<void> storeRecoveryKey(String key) =>
      _chatBackup.storeRecoveryKey(key);
  Future<void> deleteStoredRecoveryKey() =>
      _chatBackup.deleteStoredRecoveryKey();
  Future<void> disableChatBackup() => _chatBackup.disableChatBackup();
  Future<void> tryAutoUnlockBackup() => _chatBackup.tryAutoUnlockBackup();

  // ── SelectionService delegates ──────────────────────────────────

  Set<String> get selectedSpaceIds => _selection.selectedSpaceIds;
  String? get selectedRoomId => _selection.selectedRoomId;
  Room? get selectedRoom => _selection.selectedRoom;
  void selectSpace(String? spaceId) => _selection.selectSpace(spaceId);
  void toggleSpaceSelection(String spaceId) =>
      _selection.toggleSpaceSelection(spaceId);
  void clearSpaceSelection() => _selection.clearSpaceSelection();
  void selectRoom(String? roomId) => _selection.selectRoom(roomId);
  void updateSpaceOrder(List<String> order) =>
      _selection.updateSpaceOrder(order);
  List<SpaceNode> get spaceTree => _selection.spaceTree;
  List<Room> get spaces => _selection.spaces;
  List<Room> get topLevelSpaces => _selection.topLevelSpaces;
  List<Room> get rooms => _selection.rooms;
  List<Room> get invitedRooms => _selection.invitedRooms;
  List<Room> get invitedSpaces => _selection.invitedSpaces;
  String? inviterDisplayName(Room room) => _selection.inviterDisplayName(room);
  List<Room> get orphanRooms => _selection.orphanRooms;
  List<Room> roomsForSpace(String spaceId) =>
      _selection.roomsForSpace(spaceId);
  Set<String> spaceMemberships(String roomId) =>
      _selection.spaceMemberships(roomId);
  int unreadCountForSpace(String spaceId) =>
      _selection.unreadCountForSpace(spaceId);
  void invalidateSpaceTree() => _selection.invalidateSpaceTree();

  // ── SyncService delegates ───────────────────────────────────────

  bool get syncing => _sync.syncing;
  String? get autoUnlockError => _sync.autoUnlockError;

  // ── AuthService delegates ───────────────────────────────────────

  String? get loginError => _auth.loginError;
  String? get postLoginSyncError => _auth.postLoginSyncError;

  @visibleForTesting
  Future<void>? get postLoginSyncFuture => _auth.postLoginSyncFuture;

  Future<ServerAuthCapabilities> getServerAuthCapabilities(
    String homeserver,
  ) =>
      _auth.getServerAuthCapabilities(homeserver, isLoggedIn: _isLoggedIn);

  // ── Public API ──────────────────────────────────────────────────

  Future<void> init({bool restoreSession = true}) async {
    if (restoreSession) await _auth.migrateStorageKeys();
    if (restoreSession) {
      await _restoreSession();
      notifyListeners();
    }
  }

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
    _sync.cancelSyncSub();
    _uia.dispose();
    unawaited(_loginStateSub?.cancel());
    super.dispose();
  }

  // ── Login ──────────────────────────────────────────────────────

  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    _auth.loginError = null;
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
      );
      debugPrint('[Lattice] Login complete – '
          'deviceId=${_client.deviceID}, '
          'userId=${_client.userID}, '
          'encryption=${_client.encryption != null ? "available" : "null"}, '
          'encryptionEnabled=${_client.encryptionEnabled}');

      _uia.setCachedPassword(password);
      _uia.listenForUia();
      _listenForLoginState();
      _isLoggedIn = true;
      notifyListeners();

      _postLoginSync();

      return true;
    } catch (e, s) {
      debugPrint('[Lattice] Login failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      _auth.loginError = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── SSO Login ──────────────────────────────────────────────────

  Future<bool> completeSsoLogin({
    required String homeserver,
    required String loginToken,
  }) async {
    _auth.loginError = null;
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
      );
      debugPrint('[Lattice] SSO login complete – '
          'deviceId=${_client.deviceID}, '
          'userId=${_client.userID}');

      _uia.listenForUia();
      _listenForLoginState();
      _isLoggedIn = true;
      notifyListeners();

      _postLoginSync();

      return true;
    } catch (e, s) {
      debugPrint('[Lattice] SSO login failed: $e');
      debugPrint('[Lattice] Stack trace:\n$s');
      _auth.loginError = e.toString();
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

    if (password != null) _uia.setCachedPassword(password);
    _uia.listenForUia();
    _listenForLoginState();
    _isLoggedIn = true;
    notifyListeners();

    _postLoginSync();
  }

  // ── Logout ────────────────────────────────────────────────────

  Future<void> logout() async {
    unawaited(_loginStateSub?.cancel());
    _sync.cancelSyncSub();
    _isLoggedIn = false;
    await _auth.awaitPostLoginSync();

    try {
      if (_client.homeserver != null && _client.accessToken != null) {
        await _client.logout();
      }
    } catch (e) {
      debugPrint('[Lattice] Logout error: $e');
    }
    await _auth.clearSessionKeys();
    await SessionBackup.delete(clientName: clientName, storage: _storage);
    await _chatBackup.deleteStoredRecoveryKey();
    _uia.clearCachedPassword();
    _uia.cancelUiaSub();
    _selection.resetSelection();
    _chatBackup.resetChatBackupState();
    notifyListeners();
  }

  // ── Soft Logout ──────────────────────────────────────────────

  Future<void> handleSoftLogout() async {
    debugPrint('[Lattice] Soft logout detected, attempting token refresh...');
    try {
      await _client.refreshAccessToken();
      await _storage.write(
          key: latticeKey(clientName, 'access_token'),
          value: _client.accessToken,);
      await saveSessionBackup();
      debugPrint('[Lattice] Token refreshed successfully');
    } catch (e) {
      debugPrint('[Lattice] Token refresh failed: $e');
      unawaited(_loginStateSub?.cancel());
      _sync.cancelSyncSub();
      _isLoggedIn = false;
      await _auth.awaitPostLoginSync();
      _uia.cancelUiaSub();
      _uia.clearCachedPassword();
      _selection.resetSelection();
      _chatBackup.resetChatBackupState();
      await _auth.clearSessionKeys();
      await SessionBackup.delete(clientName: clientName, storage: _storage);
      await _chatBackup.deleteStoredRecoveryKey();
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
        _sync.cancelSyncSub();
        _isLoggedIn = false;
        _uia.cancelUiaSub();
        _uia.clearCachedPassword();
        _selection.resetSelection();
        _chatBackup.resetChatBackupState();
        await _auth.clearSessionKeys();
        await SessionBackup.delete(clientName: clientName, storage: _storage);
        await _chatBackup.deleteStoredRecoveryKey();
        notifyListeners();
      }
    });
  }

  // ── Private: Post-login Background Sync ─────────────────────────

  void _postLoginSync() {
    _auth.startPostLoginSync(_runPostLoginSync);
  }

  Future<void> _runPostLoginSync() async {
    try {
      await _auth.persistCredentials();
      if (!_isLoggedIn) return;
      await _sync.startSync(timeout: const Duration(minutes: 5));
      if (!_isLoggedIn) return;
      await saveSessionBackup();
    } catch (e) {
      debugPrint('[Lattice] Post-login sync error: $e');
      if (_isLoggedIn) {
        _auth.postLoginSyncError = friendlyAuthError(e);
        notifyListeners();
      }
    }
  }

  // ── Private: Initialization ─────────────────────────────────────

  Future<void> _activateSession() async {
    _uia.listenForUia();
    _listenForLoginState();
    _isLoggedIn = true;
    try {
      await _sync.startSync();
    } on TimeoutException {
      debugPrint('[Lattice] Initial sync timed out during session restore – '
          'continuing in background');
    }
  }

  // ── Private: Session Keys ──────────────────────────────────────

  Future<void> _clearSessionAndBackup() async {
    await _auth.clearSessionKeys();
    await SessionBackup.delete(clientName: clientName, storage: _storage);
  }

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

  Future<void> _restoreSession() async {
    final keys = await _readSessionKeys();

    if (keys.token == null ||
        keys.userId == null ||
        keys.homeserver == null) {
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
      if (_auth.isPermanentAuthFailure(cause)) {
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

  static Object _unwrapInitException(Object e) =>
      e is ClientInitException ? e.originalException : e;

  static bool _isExpiredTokenError(Object e) {
    if (e is MatrixException && e.errcode == 'M_UNKNOWN_TOKEN') {
      return e.errorMessage.toLowerCase().contains('expired');
    }
    return false;
  }
}

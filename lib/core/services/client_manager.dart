import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kohera/core/services/client_factory.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abstract factory for creating [MatrixService] instances with their [Client].
/// Override in tests to inject mocks.
abstract class MatrixServiceFactory {
  /// Creates a [Client] and [MatrixService] pair.
  Future<(Client, MatrixService)> create({
    required String clientName,
    FlutterSecureStorage? storage,
  });
}

/// Manages multiple [MatrixService] accounts and tracks the active one.
///
/// Persists the list of client names to [SharedPreferences] so accounts
/// survive app restarts. Sits above [MatrixService] in the provider tree.
class ClientManager extends ChangeNotifier {
  ClientManager({
    FlutterSecureStorage? storage,
    SharedPreferences? prefs,
    MatrixServiceFactory? serviceFactory,
  })  : _storage = storage ??
              const FlutterSecureStorage(
                iOptions: IOSOptions(
                  groupId: 'group.io.github.quantumheart.kohera',
                  accessibility: KeychainAccessibility.first_unlock,
                ),
                webOptions: WebOptions(
                  dbName: 'KoheraEncryptedStorage',
                  publicKey: 'KoheraSecureStorage',
                ),
              ),
        _prefs = prefs,
        _serviceFactory = serviceFactory;

  static const _clientNamesKey = 'kohera_client_names';

  final FlutterSecureStorage _storage;
  SharedPreferences? _prefs;
  final MatrixServiceFactory? _serviceFactory;

  final List<MatrixService> _services = [];
  final Map<MatrixService, Client> _clientMap = {};
  int _activeIndex = 0;
  MatrixService? _pendingService;

  List<MatrixService> get services => List.unmodifiable(_services);
  int get activeIndex => _activeIndex;

  MatrixService get activeService => _services[_activeIndex];

  MatrixService? get pendingService => _pendingService;

  bool get hasMultipleAccounts => _services.length > 1;

  // ── Initialization ───────────────────────────────────────────

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final names = _prefs!.getStringList(_clientNamesKey) ?? ['default'];

    final pairs = await Future.wait(
      names.map((name) => _createServicePair(clientName: name)),
    );
    for (final (client, service) in pairs) {
      _services.add(service);
      _clientMap[service] = client;
    }
    await Future.wait(_services.map((s) => s.init()));

    // Remove services that failed to restore (not logged in), unless it's
    // the only one left (so we still show the login screen).
    if (_services.length > 1) {
      final toRemove =
          _services.where((s) => !s.isLoggedIn).toList();
      for (final s in toRemove) {
        _services.remove(s);
        _clientMap.remove(s);
      }
      if (_services.isEmpty) {
        // All failed — create a fresh default.
        final (client, service) =
            await _createServicePair(clientName: 'default');
        await service.init(restoreSession: false);
        _services.add(service);
        _clientMap[service] = client;
      }
    }

    _activeIndex = 0;
    await _persistClientNames();
    notifyListeners();
  }

  // ── Account Switching ─────────────────────────────────────────

  void setActiveAccount(int index) {
    if (index < 0 || index >= _services.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  // ── Adding Accounts ───────────────────────────────────────────

  /// Creates a fresh [MatrixService] for a login flow (client created but
  /// no session restore). Stores it as [pendingService] — call
  /// [commitPendingService] after successful login to activate it, or
  /// [cancelPendingService] to clean up if the user cancels.
  Future<MatrixService> createLoginService() async {
    cancelPendingService();
    final name = _generateClientName();
    final (client, service) =
        await _createServicePair(clientName: name);
    _clientMap[service] = client;
    await service.init(restoreSession: false);
    _pendingService = service;
    return service;
  }

  /// Activates the pending service after a successful login.
  void commitPendingService() {
    if (_pendingService == null) return;
    _services.add(_pendingService!);
    _activeIndex = _services.length - 1;
    _pendingService = null;
    unawaited(_persistClientNames());
    notifyListeners();
  }

  /// Disposes a pending service that was never committed (user cancelled).
  void cancelPendingService() {
    if (_pendingService == null) return;
    final service = _pendingService!;
    _pendingService = null;
    final client = _clientMap.remove(service);
    service.dispose();
    unawaited(client?.dispose());
  }

  /// Adds a service (after successful login) and makes it active.
  Future<void> addService(MatrixService service) async {
    _services.add(service);
    _activeIndex = _services.length - 1;
    await _persistClientNames();
    notifyListeners();
  }

  // ── Removing Accounts ─────────────────────────────────────────

  Future<void> removeService(MatrixService service) async {
    final index = _services.indexOf(service);
    if (index == -1) return;

    _services.removeAt(index);
    final client = _clientMap.remove(service);
    service.dispose();
    await client?.dispose();

    if (_services.isEmpty) {
      // Last account removed — create a fresh default for login screen.
      final (newClient, fresh) =
          await _createServicePair(clientName: 'default');
      await fresh.init(restoreSession: false);
      _services.add(fresh);
      _clientMap[fresh] = newClient;
      _activeIndex = 0;
    } else if (_activeIndex >= _services.length) {
      _activeIndex = _services.length - 1;
    } else if (_activeIndex > index) {
      _activeIndex--;
    }

    await _persistClientNames();
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────

  Future<(Client, MatrixService)> _createServicePair({
    required String clientName,
  }) async {
    if (_serviceFactory != null) {
      return _serviceFactory!.create(
        clientName: clientName,
        storage: _storage,
      );
    }
    // Create service first with a placeholder client so we can wire the
    // soft-logout callback to reference the service. Then replace via the
    // actual factory call.
    late final MatrixService service;
    final client = await createDefaultClient(
      clientName,
      onSoftLogout: (_) async => service.handleSoftLogout(),
    );
    service = MatrixService(
      client: client,
      clientName: clientName,
      storage: _storage,
    );
    return (client, service);
  }

  String _generateClientName() {
    final existing = _services.map((s) => s.clientName).toSet();
    var i = 1;
    while (existing.contains('account_$i')) {
      i++;
    }
    return 'account_$i';
  }

  Future<void> _persistClientNames() async {
    final names = _services.map((s) => s.clientName).toList();
    await _prefs?.setStringList(_clientNamesKey, names);
  }

  @override
  void dispose() {
    for (final service in _services) {
      unawaited(_clientMap[service]?.dispose());
      service.dispose();
    }
    super.dispose();
  }
}

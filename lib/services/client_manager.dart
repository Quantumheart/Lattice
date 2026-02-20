import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'matrix_service.dart';

/// Factory function for creating [MatrixService] instances.
/// Overridden in tests to inject mocks.
typedef MatrixServiceFactory = MatrixService Function({
  required String clientName,
  FlutterSecureStorage? storage,
});

/// Manages multiple [MatrixService] accounts and tracks the active one.
///
/// Persists the list of client names to [SharedPreferences] so accounts
/// survive app restarts. Sits above [MatrixService] in the provider tree.
class ClientManager extends ChangeNotifier {
  ClientManager({
    FlutterSecureStorage? storage,
    SharedPreferences? prefs,
    MatrixServiceFactory? serviceFactory,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _prefs = prefs,
        _serviceFactory = serviceFactory;

  static const _clientNamesKey = 'lattice_client_names';

  final FlutterSecureStorage _storage;
  SharedPreferences? _prefs;
  final MatrixServiceFactory? _serviceFactory;

  final List<MatrixService> _services = [];
  int _activeIndex = 0;

  List<MatrixService> get services => List.unmodifiable(_services);
  int get activeIndex => _activeIndex;

  MatrixService get activeService => _services[_activeIndex];

  bool get hasMultipleAccounts => _services.length > 1;

  // ── Initialization ───────────────────────────────────────────

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final names = _prefs!.getStringList(_clientNamesKey) ?? ['default'];

    for (final name in names) {
      final service = _createService(clientName: name);
      await service.init();
      _services.add(service);
    }

    // Remove services that failed to restore (not logged in), unless it's
    // the only one left (so we still show the login screen).
    if (_services.length > 1) {
      _services.removeWhere((s) => !s.isLoggedIn);
      if (_services.isEmpty) {
        // All failed — create a fresh default.
        _services.add(_createService(clientName: 'default'));
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
  /// no session restore). The caller should call [addService] after a
  /// successful login.
  Future<MatrixService> createLoginService() async {
    final name = _generateClientName();
    final service = _createService(clientName: name);
    await service.initClient();
    return service;
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
    service.dispose();

    if (_services.isEmpty) {
      // Last account removed — create a fresh default for login screen.
      final fresh = _createService(clientName: 'default');
      await fresh.initClient();
      _services.add(fresh);
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

  MatrixService _createService({required String clientName}) {
    if (_serviceFactory != null) {
      return _serviceFactory!(clientName: clientName, storage: _storage);
    }
    return MatrixService(clientName: clientName, storage: _storage);
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
      service.dispose();
    }
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lattice/core/models/server_auth_capabilities.dart';
import 'package:lattice/core/services/matrix_service.dart' show latticeKey;
import 'package:matrix/matrix.dart';
// ignore: implementation_imports, no public API for ClientInitException
import 'package:matrix/src/utils/client_init_exception.dart';

class AuthService {
  AuthService({
    required Client client,
    required FlutterSecureStorage storage,
    required String clientName,
  })  : _client = client,
        _storage = storage,
        _clientName = clientName;

  final Client _client;
  final FlutterSecureStorage _storage;
  final String _clientName;

  // ── Auth state ────────────────────────────────────────────────
  String? loginError;
  String? postLoginSyncError;

  Completer<void>? _postLoginSyncCompleter;

  Future<void>? get postLoginSyncFuture => _postLoginSyncCompleter?.future;

  Completer<void>? _capabilitiesLock;

  // ── Server Capabilities ──────────────────────────────────────

  Future<ServerAuthCapabilities> getServerAuthCapabilities(
    String homeserver, {
    required bool isLoggedIn,
  }) async {
    if (isLoggedIn) {
      debugPrint('[Lattice] getServerAuthCapabilities called while logged in, '
          'skipping to avoid mutating shared client state');
      return const ServerAuthCapabilities();
    }

    var hs = homeserver.trim();
    if (hs.isEmpty) throw ArgumentError('Homeserver cannot be empty');
    if (!hs.startsWith('http')) hs = 'https://$hs';

    while (_capabilitiesLock != null) {
      await _capabilitiesLock!.future;
    }
    final lock = Completer<void>();
    _capabilitiesLock = lock;

    final previousHomeserver = _client.homeserver;
    try {
      await _client.checkHomeserver(Uri.parse(hs));

      final loginFlows = await _client.getLoginFlows();
      final supportsPassword =
          loginFlows?.any((f) => f.type == AuthenticationTypes.password) ??
              false;
      final supportsSso =
          loginFlows?.any((f) => f.type == AuthenticationTypes.sso) ?? false;

      final ssoFlow = loginFlows
          ?.where((f) => f.type == AuthenticationTypes.sso)
          .firstOrNull;
      final idProviders = <SsoIdentityProvider>[];
      if (ssoFlow != null) {
        final providers = ssoFlow.additionalProperties['identity_providers'];
        if (providers is List) {
          for (final p in providers) {
            if (p is Map && p['id'] is String && p['name'] is String) {
              idProviders.add(SsoIdentityProvider(
                id: p['id'] as String,
                name: p['name'] as String,
                icon: p['icon'] as String?,
              ),);
            }
          }
        }
      }

      var supportsRegistration = false;
      var registrationStages = <String>[];
      try {
        await _client.request(
          RequestType.POST,
          '/client/v3/register',
          data: <String, dynamic>{},
        );
      } on MatrixException catch (e) {
        if (e.raw.containsKey('flows')) {
          supportsRegistration = true;
          final flows = e.raw['flows'];
          if (flows is List && flows.isNotEmpty) {
            final allStages = <String>{};
            for (final flow in flows) {
              if (flow is Map && flow['stages'] is List) {
                allStages.addAll((flow['stages'] as List).cast<String>());
              }
            }
            registrationStages = allStages.toList();
          }
        }
      } catch (_) {}

      final resolvedHomeserver = _client.homeserver;

      return ServerAuthCapabilities(
        supportsPassword: supportsPassword,
        supportsSso: supportsSso,
        supportsRegistration: supportsRegistration,
        ssoIdentityProviders: idProviders,
        registrationStages: registrationStages,
        resolvedHomeserver: resolvedHomeserver,
      );
    } finally {
      _client.homeserver = previousHomeserver;
      lock.complete();
      _capabilitiesLock = null;
    }
  }

  // ── Session Key Management ────────────────────────────────────

  bool isPermanentAuthFailure(Object error) {
    final e =
        error is ClientInitException ? error.originalException : error;
    if (e is MatrixException) {
      return e.errcode == 'M_UNKNOWN_TOKEN' ||
          e.errcode == 'M_FORBIDDEN' ||
          e.errcode == 'M_USER_DEACTIVATED';
    }
    return false;
  }

  Future<void> clearSessionKeys() async {
    await Future.wait([
      _storage.delete(key: latticeKey(_clientName, 'access_token')),
      _storage.delete(key: latticeKey(_clientName, 'refresh_token')),
      _storage.delete(key: latticeKey(_clientName, 'user_id')),
      _storage.delete(key: latticeKey(_clientName, 'homeserver')),
      _storage.delete(key: latticeKey(_clientName, 'device_id')),
      _storage.delete(key: latticeKey(_clientName, 'olm_account')),
    ]);
  }

  // ── Storage Key Migration ─────────────────────────────────────

  Future<void> migrateStorageKeys() async {
    if (_clientName != 'default') return;

    final oldToken = await _storage.read(key: 'lattice_access_token');
    if (oldToken == null) return;

    debugPrint('[Lattice] Migrating old storage keys to namespaced format');

    const migrations = {
      'lattice_access_token': 'lattice_default_access_token',
      'lattice_user_id': 'lattice_default_user_id',
      'lattice_homeserver': 'lattice_default_homeserver',
      'lattice_device_id': 'lattice_default_device_id',
      'lattice_olm_account': 'lattice_default_olm_account',
    };

    for (final entry in migrations.entries) {
      final value = await _storage.read(key: entry.key);
      if (value != null) {
        await _storage.write(key: entry.value, value: value);
        await _storage.delete(key: entry.key);
      }
    }
  }

  // ── Credential Persistence ──────────────────────────────────

  Future<void> persistCredentials() async {
    final stored = await _client.database.getClient(_clientName);
    final refreshToken = stored?.tryGet<String>('refresh_token');
    await Future.wait([
      _storage.write(
          key: latticeKey(_clientName, 'access_token'),
          value: _client.accessToken,),
      _storage.write(
          key: latticeKey(_clientName, 'refresh_token'),
          value: refreshToken,),
      _storage.write(
          key: latticeKey(_clientName, 'user_id'), value: _client.userID,),
      _storage.write(
          key: latticeKey(_clientName, 'homeserver'),
          value: _client.homeserver.toString(),),
      _storage.write(
          key: latticeKey(_clientName, 'device_id'), value: _client.deviceID,),
    ]);
  }

  // ── Post-login Background Sync ──────────────────────────────

  void startPostLoginSync(Future<void> Function() runSync) {
    postLoginSyncError = null;
    final completer = Completer<void>();
    _postLoginSyncCompleter = completer;
    unawaited(runSync().whenComplete(() {
      completer.complete();
      _postLoginSyncCompleter = null;
    },),);
  }

  Future<void> awaitPostLoginSync() async {
    await _postLoginSyncCompleter?.future;
  }

}

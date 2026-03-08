import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/models/server_auth_capabilities.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/auth/screens/homeserver_screen.dart';
import 'package:lattice/features/auth/screens/login_screen.dart';
import 'package:lattice/features/auth/screens/registration_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'mocks.dart';

// ── FixedServiceFactory ─────────────────────────────────────────────────────

class FixedServiceFactory extends MatrixServiceFactory {
  FixedServiceFactory(this._service);
  final MatrixService _service;

  @override
  Future<(Client, MatrixService)> create({
    required String clientName,
    FlutterSecureStorage? storage,
  }) async {
    return (_service.client, _service);
  }
}

// ── Stubs ────────────────────────────────────────────────────────────────────

void stubPasswordServer(MockClient mockClient) {
  when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
        null,
        GetVersionsResponse.fromJson({'versions': ['v1.1']}),
        <LoginFlow>[],
        null,
      ));
  when(mockClient.getLoginFlows()).thenAnswer((_) async => [
        LoginFlow(type: AuthenticationTypes.password),
      ]);
  when(mockClient.register()).thenThrow(
    MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'Registration is not enabled',
    }),
  );
}

void stubSsoServer(
  MockClient mockClient, {
  List<Map<String, String>> providers = const [],
}) {
  when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
        null,
        GetVersionsResponse.fromJson({'versions': ['v1.1']}),
        <LoginFlow>[],
        null,
      ));
  when(mockClient.getLoginFlows()).thenAnswer((_) async => [
        LoginFlow(
          type: AuthenticationTypes.sso,
          additionalProperties: {
            if (providers.isNotEmpty) 'identity_providers': providers,
          },
        ),
      ]);
  when(mockClient.register()).thenThrow(
    MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'Registration is not enabled',
    }),
  );
}

void stubSuccessfulLogin(
  MockClient mockClient,
  CachedStreamController<SyncUpdate> syncController,
) {
  when(mockClient.login(
    LoginType.mLoginPassword,
    identifier: anyNamed('identifier'),
    password: anyNamed('password'),
    initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
  )).thenAnswer((_) async => LoginResponse(
        accessToken: 'token_123',
        deviceId: 'DEVICE_1',
        userId: '@alice:matrix.org',
      ));
  when(mockClient.userID).thenReturn('@alice:matrix.org');
  when(mockClient.deviceID).thenReturn('DEVICE_1');
  when(mockClient.accessToken).thenReturn('token_123');
  when(mockClient.homeserver).thenReturn(Uri.parse('https://matrix.org'));
  when(mockClient.encryption).thenReturn(null);
  when(mockClient.encryptionEnabled).thenReturn(false);
  when(mockClient.onLoginStateChanged)
      .thenReturn(CachedStreamController<LoginState>());
  when(mockClient.onUiaRequest)
      .thenReturn(CachedStreamController<UiaRequest>());
  when(mockClient.onSync).thenReturn(syncController);
}

void stubFailedLogin(MockClient mockClient) {
  when(mockClient.login(
    LoginType.mLoginPassword,
    identifier: anyNamed('identifier'),
    password: anyNamed('password'),
    initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
  )).thenThrow(
    MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'Invalid username or password',
    }),
  );
}

void stubServerCheckFailure(MockClient mockClient) {
  when(mockClient.checkHomeserver(any))
      .thenThrow(Exception('Connection failed'));
}

// ── Test app builder ─────────────────────────────────────────────────────────

Widget buildTestApp({
  required MatrixService matrixService,
  required ClientManager clientManager,
  required ValueNotifier<bool> navigatedToHome,
}) {
  navigatedToHome.value = false;

  final router = GoRouter(
    refreshListenable: matrixService,
    initialLocation: '/login',
    redirect: (context, state) {
      if (matrixService.isLoggedIn &&
          state.matchedLocation.startsWith('/login')) {
        navigatedToHome.value = true;
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: Routes.login,
        builder: (context, state) => HomeserverScreen(key: ValueKey(state.uri)),
        routes: [
          GoRoute(
            path: ':homeserver',
            name: Routes.loginServer,
            builder: (context, state) {
              final homeserver = state.pathParameters['homeserver']!;
              final capabilities = state.extra as ServerAuthCapabilities? ??
                  const ServerAuthCapabilities(supportsPassword: true);
              return LoginScreen(
                homeserver: homeserver,
                capabilities: capabilities,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/register',
        name: Routes.register,
        builder: (context, state) {
          final homeserver = state.extra as String? ?? 'matrix.org';
          return RegistrationScreen(initialHomeserver: homeserver);
        },
      ),
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Home'))),
      ),
    ],
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MatrixService>.value(value: matrixService),
      ChangeNotifierProvider<ClientManager>.value(value: clientManager),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<void> completePostLoginSync(
  WidgetTester tester,
  MatrixService matrixService,
  CachedStreamController<SyncUpdate> syncController,
) async {
  syncController.add(SyncUpdate(nextBatch: 'batch_1', rooms: RoomsUpdate()));
  await tester.pumpAndSettle();
  await matrixService.postLoginSyncFuture;
  matrixService.dispose();
}

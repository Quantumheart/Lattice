import 'dart:async';

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
import 'package:lattice/features/rooms/widgets/new_room_dialog.dart';
import 'package:lattice/features/rooms/widgets/room_details_panel.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'mocks.dart' show MockClient, MockRoom;

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

// ── Room stubs ───────────────────────────────────────────────────────────────

void stubLoggedInClient(
  MockClient mockClient,
  CachedStreamController<SyncUpdate> syncController,
) {
  when(mockClient.userID).thenReturn('@alice:matrix.org');
  when(mockClient.homeserver).thenReturn(Uri.parse('https://matrix.org'));
  when(mockClient.accessToken).thenReturn('token_123');
  when(mockClient.encryption).thenReturn(null);
  when(mockClient.encryptionEnabled).thenReturn(false);
  when(mockClient.updateUserDeviceKeys()).thenAnswer((_) async {});
  when(mockClient.userDeviceKeys).thenReturn({});
  when(mockClient.onLoginStateChanged)
      .thenReturn(CachedStreamController<LoginState>());
  when(mockClient.onUiaRequest)
      .thenReturn(CachedStreamController<UiaRequest>());
  when(mockClient.onSync).thenReturn(syncController);
}

void stubRoomDefaults(MockRoom mockRoom, MockClient mockClient) {
  when(mockRoom.id).thenReturn('!room:example.com');
  when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
  when(mockRoom.client).thenReturn(mockClient);
  when(mockRoom.topic).thenReturn('');
  when(mockRoom.avatar).thenReturn(null);
  when(mockRoom.encrypted).thenReturn(false);
  when(mockRoom.isDirectChat).thenReturn(false);
  when(mockRoom.isFavourite).thenReturn(false);
  when(mockRoom.pushRuleState).thenReturn(PushRuleState.notify);
  when(mockRoom.canChangeStateEvent(any)).thenReturn(false);
  when(mockRoom.canChangePowerLevel).thenReturn(false);
  when(mockRoom.canKick).thenReturn(false);
  when(mockRoom.canBan).thenReturn(false);
  when(mockRoom.summary).thenReturn(
    RoomSummary.fromJson({'m.joined_member_count': 3}),
  );
  when(mockRoom.requestParticipants(any)).thenAnswer((_) async => []);
  when(mockRoom.getPowerLevelByUserId(any)).thenReturn(0);
}

void stubCreateRoom(MockClient mockClient, {String newRoomId = '!newroom:example.com'}) {
  when(mockClient.createRoom(
    name: anyNamed('name'),
    topic: anyNamed('topic'),
    visibility: anyNamed('visibility'),
    initialState: anyNamed('initialState'),
    invite: anyNamed('invite'),
  )).thenAnswer((_) async => newRoomId);
  when(mockClient.waitForRoomInSync(any, join: anyNamed('join')))
      .thenAnswer((_) async => SyncUpdate(nextBatch: ''));
}

// ── Room test app builder ────────────────────────────────────────────────────

Widget buildRoomTestApp({
  required MatrixService matrixService,
  required ClientManager clientManager,
}) {
  final router = GoRouter(
    refreshListenable: matrixService,
    initialLocation: '/',
    redirect: (context, state) {
      final roomId = matrixService.selectedRoomId;
      if (roomId != null && state.matchedLocation == '/') {
        return '/rooms/$roomId';
      }
      if (roomId == null && state.matchedLocation.startsWith('/rooms/')) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Home')),
          floatingActionButton: Builder(
            builder: (context) => FloatingActionButton(
              onPressed: () {
                unawaited(NewRoomDialog.show(
                  context,
                  matrixService: matrixService,
                ));
              },
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/rooms/:roomId',
        builder: (context, state) {
          final roomId = state.pathParameters['roomId']!;
          final room = matrixService.client.getRoomById(roomId);
          final name = room?.getLocalizedDisplayname() ?? 'Unknown';
          return Scaffold(
            appBar: AppBar(
              title: Text(name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => context.go('/rooms/$roomId/details'),
                ),
              ],
            ),
            body: Center(child: Text(name)),
          );
        },
        routes: [
          GoRoute(
            path: 'details',
            builder: (context, state) {
              final roomId = state.pathParameters['roomId']!;
              return RoomDetailsPanel(roomId: roomId, isFullPage: true);
            },
          ),
        ],
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

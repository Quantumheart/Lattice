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

import '../services/matrix_service_test.mocks.dart';

class _FixedServiceFactory extends MatrixServiceFactory {
  _FixedServiceFactory(this._service);
  final MatrixService _service;

  @override
  Future<(Client, MatrixService)> create({
    required String clientName,
    FlutterSecureStorage? storage,
  }) async {
    return (_service.client, _service);
  }
}

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;

  late CachedStreamController<SyncUpdate> syncController;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    matrixService = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
    clientManager = ClientManager(
      storage: mockStorage,
      serviceFactory: _FixedServiceFactory(matrixService),
    );
    syncController = CachedStreamController<SyncUpdate>();
  });

  // ── Stubs ────────────────────────────────────────────────────────────────

  void stubPasswordServer() {
    when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
          null,
          GetVersionsResponse.fromJson({
            'versions': ['v1.1'],
          }),
          <LoginFlow>[],
          null,
        ),);
    when(mockClient.getLoginFlows()).thenAnswer((_) async => [
          LoginFlow(type: AuthenticationTypes.password),
        ],);
    when(mockClient.register()).thenThrow(
      MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Registration is not enabled',
      }),
    );
  }

  void stubSsoServer({List<Map<String, String>> providers = const []}) {
    when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
          null,
          GetVersionsResponse.fromJson({
            'versions': ['v1.1'],
          }),
          <LoginFlow>[],
          null,
        ),);
    when(mockClient.getLoginFlows()).thenAnswer((_) async => [
          LoginFlow(
            type: AuthenticationTypes.sso,
            additionalProperties: {
              if (providers.isNotEmpty) 'identity_providers': providers,
            },
          ),
        ],);
    when(mockClient.register()).thenThrow(
      MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Registration is not enabled',
      }),
    );
  }

  void stubPasswordAndSsoServer({
    List<Map<String, String>> providers = const [],
  }) {
    when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
          null,
          GetVersionsResponse.fromJson({
            'versions': ['v1.1'],
          }),
          <LoginFlow>[],
          null,
        ),);
    when(mockClient.getLoginFlows()).thenAnswer((_) async => [
          LoginFlow(type: AuthenticationTypes.password),
          LoginFlow(
            type: AuthenticationTypes.sso,
            additionalProperties: {
              if (providers.isNotEmpty) 'identity_providers': providers,
            },
          ),
        ],);
    when(mockClient.register()).thenThrow(
      MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Registration is not enabled',
      }),
    );
  }

  void stubSuccessfulLogin() {
    when(mockClient.login(
      LoginType.mLoginPassword,
      identifier: anyNamed('identifier'),
      password: anyNamed('password'),
      initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
    ),).thenAnswer((_) async => LoginResponse(
          accessToken: 'token_123',
          deviceId: 'DEVICE_1',
          userId: '@alice:matrix.org',
        ),);
    when(mockClient.userID).thenReturn('@alice:matrix.org');
    when(mockClient.deviceID).thenReturn('DEVICE_1');
    when(mockClient.accessToken).thenReturn('token_123');
    when(mockClient.homeserver).thenReturn(Uri.parse('https://matrix.org'));
    when(mockClient.encryption).thenReturn(null);
    when(mockClient.encryptionEnabled).thenReturn(false);
    when(mockClient.onLoginStateChanged)
        .thenReturn(CachedStreamController<LoginState>());
    when(mockClient.onUiaRequest)
        .thenReturn(CachedStreamController<UiaRequest<dynamic>>());
    when(mockClient.onSync).thenReturn(syncController);
  }

  void stubFailedLogin() {
    when(mockClient.login(
      LoginType.mLoginPassword,
      identifier: anyNamed('identifier'),
      password: anyNamed('password'),
      initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
    ),).thenThrow(
      MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Invalid username or password',
      }),
    );
  }

  void stubServerCheckFailure() {
    when(mockClient.checkHomeserver(any))
        .thenThrow(Exception('Connection failed'));
  }

  // ── Test app builder ─────────────────────────────────────────────────────

  var navigatedToHome = false;

  Widget buildApp() {
    navigatedToHome = false;

    final router = GoRouter(
      refreshListenable: matrixService,
      initialLocation: '/login',
      redirect: (context, state) {
        if (matrixService.isLoggedIn &&
            state.matchedLocation.startsWith('/login')) {
          navigatedToHome = true;
          return '/home';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          name: Routes.login,
          builder: (context, state) => const HomeserverScreen(),
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
          path: '/home',
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

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> completePostLoginSync(WidgetTester tester) async {
    syncController.add(SyncUpdate(nextBatch: 'batch_1', rooms: RoomsUpdate()));
    await tester.pumpAndSettle();
    await matrixService.postLoginSyncFuture;
    matrixService.dispose();
  }

  // ── E2E Tests ────────────────────────────────────────────────────────────

  group('Login E2E — homeserver to login complete', () {
    testWidgets('successful password login navigates through full flow',
        (tester) async {
      stubPasswordServer();
      stubSuccessfulLogin();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(HomeserverScreen), findsOneWidget);
      expect(find.text('matrix.org'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign in to matrix.org'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Username'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret123',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(navigatedToHome, isTrue);
      await completePostLoginSync(tester);
    });

    testWidgets('custom homeserver carries through to login screen',
        (tester) async {
      stubPasswordServer();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'custom-server.org');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign in to custom-server.org'), findsOneWidget);
      expect(find.text('custom-server.org'), findsWidgets);
    });

    testWidgets('failed server check stays on homeserver screen',
        (tester) async {
      stubServerCheckFailure();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeserverScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('failed login shows error and stays on login screen',
        (tester) async {
      stubPasswordServer();
      stubFailedLogin();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Username'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'wrong_password',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(navigatedToHome, isFalse);
    });

    testWidgets('SSO-only server shows SSO buttons on login screen',
        (tester) async {
      stubSsoServer(providers: [
        {'id': 'google', 'name': 'Google'},
      ],);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Sign In'), findsNothing);
    });

    testWidgets('password+SSO server shows both options', (tester) async {
      stubPasswordAndSsoServer(providers: [
        {'id': 'oidc', 'name': 'OIDC Provider'},
      ],);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Sign in with OIDC Provider'), findsOneWidget);
      expect(find.text('or'), findsOneWidget);
    });

    testWidgets('homeserver chip navigates back to homeserver screen',
        (tester) async {
      stubPasswordServer();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();

      expect(find.byType(HomeserverScreen), findsOneWidget);
    });

    testWidgets('Create an account navigates to registration screen',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationScreen), findsOneWidget);
    });

    testWidgets('login via keyboard submit on password field', (tester) async {
      stubPasswordServer();
      stubSuccessfulLogin();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Username'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(navigatedToHome, isTrue);
      await completePostLoginSync(tester);
    });

    testWidgets('password visibility toggle works on login screen',
        (tester) async {
      stubPasswordServer();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final passwordField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Password'),
      );
      expect(passwordField.obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      final updatedField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Password'),
      );
      expect(updatedField.obscureText, isFalse);
    });

    testWidgets('retry login after initial failure succeeds', (tester) async {
      stubPasswordServer();
      stubFailedLogin();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Username'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'wrong',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(navigatedToHome, isFalse);

      stubSuccessfulLogin();

      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'correct',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(navigatedToHome, isTrue);
      await completePostLoginSync(tester);
    });

    testWidgets('homeserver submit via keyboard navigates to login',
        (tester) async {
      stubPasswordServer();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:lattice/core/models/server_auth_capabilities.dart';
import 'package:lattice/core/routing/app_router.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/auth/screens/homeserver_screen.dart';
import 'package:lattice/features/auth/screens/login_screen.dart';
import 'package:lattice/features/chat/services/opengraph_service.dart';

import '../test/services/matrix_service_test.mocks.dart';

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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;

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
  });

  void stubPasswordServer() {
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

  void stubLoginSuccess() {
    when(mockClient.login(
      LoginType.mLoginPassword,
      identifier: anyNamed('identifier'),
      password: anyNamed('password'),
      initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
    )).thenAnswer((_) async => LoginResponse.fromJson({
          'access_token': 'test_token',
          'device_id': 'TESTDEVICE',
          'user_id': '@alice:matrix.org',
        }));
    when(mockClient.userID).thenReturn('@alice:matrix.org');
    when(mockClient.isLogged()).thenReturn(true);
  }

  void stubLoginFailure() {
    when(mockClient.login(
      LoginType.mLoginPassword,
      identifier: anyNamed('identifier'),
      password: anyNamed('password'),
      initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
    )).thenThrow(MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'Invalid username or password',
    }));
  }

  Widget buildApp() {
    final router = GoRouter(
      refreshListenable: matrixService,
      initialLocation: '/login',
      redirect: (context, state) {
        final loggedIn = matrixService.isLoggedIn;
        final onAuthRoute = state.matchedLocation.startsWith('/login') ||
            state.matchedLocation.startsWith('/register');
        if (!loggedIn && !onAuthRoute) return '/login';
        if (loggedIn && onAuthRoute) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) =>
              HomeserverScreen(key: ValueKey(state.uri)),
          routes: [
            GoRoute(
              path: ':homeserver',
              name: 'login-server',
              builder: (context, state) {
                final homeserver = state.pathParameters['homeserver']!;
                final capabilities =
                    state.extra as ServerAuthCapabilities? ??
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
          path: '/',
          name: 'home',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Home Screen')),
          ),
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
        ChangeNotifierProvider(create: (_) => PreferencesService()),
        Provider(
          create: (_) => OpenGraphService(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  // ── Tests ─────────────────────────────────────────────────────

  group('Auth flow E2E', () {
    testWidgets('homeserver screen renders with defaults', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Connect to the Matrix network'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, 'matrix.org');
    });

    testWidgets('homeserver check → navigates to login screen', (tester) async {
      stubPasswordServer();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign in to matrix.org'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('homeserver check failure shows error', (tester) async {
      when(mockClient.checkHomeserver(any))
          .thenThrow(Exception('Connection failed'));

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeserverScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('custom homeserver → navigates to login for that server',
        (tester) async {
      stubPasswordServer();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'custom.server.org');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign in to custom.server.org'), findsOneWidget);
    });

    testWidgets('full login flow: homeserver → credentials → success',
        (tester) async {
      stubPasswordServer();
      stubLoginSuccess();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Step 1: Select homeserver
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      // Step 2: Enter credentials
      await tester.enterText(
        find.widgetWithText(TextField, 'Username'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret123',
      );

      // Step 3: Submit login
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Verify login was called with correct args
      verify(mockClient.login(
        LoginType.mLoginPassword,
        identifier: anyNamed('identifier'),
        password: anyNamed('password'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).called(1);
    });

    testWidgets('login failure shows error and stays on login screen',
        (tester) async {
      stubPasswordServer();
      stubLoginFailure();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Navigate to login
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Enter credentials and submit
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

      // Should stay on login screen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      stubPasswordServer();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Password should be obscured by default
      final passwordField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Password'),
      );
      expect(passwordField.obscureText, isTrue);

      // Tap visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      // Password should now be visible
      final updatedField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Password'),
      );
      expect(updatedField.obscureText, isFalse);
    });

    testWidgets('SSO-only server shows SSO button without password fields',
        (tester) async {
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
                'identity_providers': [
                  {'id': 'google', 'name': 'Google'},
                ],
              },
            ),
          ]);
      when(mockClient.register()).thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'Registration is not enabled',
        }),
      );

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Sign In'), findsNothing);
      expect(find.widgetWithText(TextField, 'Username'), findsNothing);
      expect(find.widgetWithText(TextField, 'Password'), findsNothing);
    });

    testWidgets('login screen back navigation returns to homeserver screen',
        (tester) async {
      stubPasswordServer();

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Navigate to login
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      // Tap the homeserver chip to go back
      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();

      expect(find.byType(HomeserverScreen), findsOneWidget);
    });
  });
}

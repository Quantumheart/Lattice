import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:lattice/screens/homeserver_screen.dart';
import 'package:lattice/screens/login_screen.dart';
import 'package:lattice/screens/registration_screen.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/services/client_manager.dart';

import '../services/matrix_service_test.mocks.dart';

void main() {
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
      serviceFactory: ({required String clientName, storage, clientFactory}) =>
          matrixService,
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

  Widget buildTestWidget() {
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) => const HomeserverScreen(),
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
          path: '/register',
          name: 'register',
          builder: (context, state) {
            final homeserver = state.extra as String? ?? 'matrix.org';
            return RegistrationScreen(initialHomeserver: homeserver);
          },
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  group('HomeserverScreen', () {
    testWidgets('shows subtitle and Continue button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Connect to the Matrix network'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('shows default homeserver text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, 'matrix.org');
    });

    testWidgets('navigates to LoginScreen on successful server check',
        (tester) async {
      stubPasswordServer();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('shows error on server check failure', (tester) async {
      when(mockClient.checkHomeserver(any))
          .thenThrow(Exception('Connection failed'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Should stay on HomeserverScreen with an error
      expect(find.byType(HomeserverScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('shows Create an account button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Create an account'), findsOneWidget);
    });

    testWidgets('navigates to RegistrationScreen with homeserver',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Change homeserver text before navigating.
      await tester.enterText(find.byType(TextField), 'custom.org');

      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationScreen), findsOneWidget);
    });
  });
}

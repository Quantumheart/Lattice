import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/auth/screens/homeserver_screen.dart';
import 'package:lattice/features/auth/screens/login_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import 'helpers/mocks.dart';
import 'helpers/test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  loginFlowTests();
}

void loginFlowTests() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;
  late CachedStreamController<SyncUpdate> syncController;
  late ValueNotifier<bool> navigatedToHome;

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
      serviceFactory: FixedServiceFactory(matrixService),
    );
    syncController = CachedStreamController<SyncUpdate>();
    navigatedToHome = ValueNotifier(false);
  });

  // ── Integration Tests ──────────────────────────────────────────────────────

  group('Login integration — homeserver to login complete', () {
    testWidgets('successful password login navigates through full flow',
        (tester) async {
      stubPasswordServer(mockClient);
      stubSuccessfulLogin(mockClient, syncController);

      await tester.pumpWidget(buildTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
        navigatedToHome: navigatedToHome,
      ),);
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

      expect(navigatedToHome.value, isTrue);
      await completePostLoginSync(tester, matrixService, syncController);
    });

    testWidgets('custom homeserver carries through to login screen',
        (tester) async {
      stubPasswordServer(mockClient);

      await tester.pumpWidget(buildTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
        navigatedToHome: navigatedToHome,
      ),);
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
      stubServerCheckFailure(mockClient);

      await tester.pumpWidget(buildTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
        navigatedToHome: navigatedToHome,
      ),);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeserverScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('failed login shows error and stays on login screen',
        (tester) async {
      stubPasswordServer(mockClient);
      stubFailedLogin(mockClient);

      await tester.pumpWidget(buildTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
        navigatedToHome: navigatedToHome,
      ),);
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
      expect(navigatedToHome.value, isFalse);
    });

    testWidgets('SSO-only server shows SSO buttons on login screen',
        (tester) async {
      stubSsoServer(mockClient, providers: [
        {'id': 'google', 'name': 'Google'},
      ],);

      await tester.pumpWidget(buildTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
        navigatedToHome: navigatedToHome,
      ),);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Sign In'), findsNothing);
    });

    testWidgets('retry after failure succeeds', (tester) async {
      stubPasswordServer(mockClient);
      stubFailedLogin(mockClient);

      await tester.pumpWidget(buildTestApp(
        matrixService: matrixService,
        clientManager: clientManager,
        navigatedToHome: navigatedToHome,
      ),);
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
      expect(navigatedToHome.value, isFalse);

      stubSuccessfulLogin(mockClient, syncController);

      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'correct',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(navigatedToHome.value, isTrue);
      await completePostLoginSync(tester, matrixService, syncController);
    });
  });
}

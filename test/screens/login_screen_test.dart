import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/models/server_auth_capabilities.dart';
import 'package:lattice/core/services/app_config.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/auth/screens/login_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late PreferencesService prefsService;

  setUp(() async {
    AppConfig.setInstance(AppConfig.testInstance());
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefsService = PreferencesService(prefs: sp);
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
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

  tearDown(AppConfig.reset);

  Widget buildTestWidget({
    String homeserver = 'matrix.org',
    ServerAuthCapabilities capabilities = const ServerAuthCapabilities(
      supportsPassword: true,
    ),
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider(create: (ctx) => CallService(client: ctx.read<MatrixService>().client)),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
        ChangeNotifierProvider<PreferencesService>.value(value: prefsService),
      ],
      child: MaterialApp(
        home: LoginScreen(
          homeserver: homeserver,
          capabilities: capabilities,
        ),
      ),
    );
  }

  group('LoginScreen', () {
    testWidgets('shows homeserver chip with correct text', (tester) async {
      await tester.pumpWidget(buildTestWidget(homeserver: 'my-server.org'));
      await tester.pumpAndSettle();

      expect(find.text('my-server.org'), findsOneWidget);
      expect(find.byType(ActionChip), findsOneWidget);
    });

    testWidgets('shows Sign In button when server supports password',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('shows SSO button when server supports SSO', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        capabilities: const ServerAuthCapabilities(
          supportsSso: true,
          ssoIdentityProviders: [
            SsoIdentityProvider(id: 'google', name: 'Google'),
          ],
        ),
      ),);
      await tester.pumpAndSettle();

      expect(find.text('Sign in with Google'), findsOneWidget);
      // No password fields when only SSO is supported
      expect(find.text('Sign In'), findsNothing);
    });

    testWidgets('shows both SSO and password when server supports both',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        capabilities: const ServerAuthCapabilities(
          supportsPassword: true,
          supportsSso: true,
          ssoIdentityProviders: [
            SsoIdentityProvider(id: 'oidc', name: 'OIDC Provider'),
          ],
        ),
      ),);
      await tester.pumpAndSettle();

      expect(find.text('Sign in with OIDC Provider'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('or'), findsOneWidget);
    });
  });
}

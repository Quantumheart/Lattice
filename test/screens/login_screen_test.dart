import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:lattice/screens/login_screen.dart';
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

  Widget buildTestWidget({
    String homeserver = 'matrix.org',
    ServerAuthCapabilities capabilities = const ServerAuthCapabilities(
      supportsPassword: true,
    ),
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
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
      ));
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
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sign in with OIDC Provider'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('or'), findsOneWidget);
    });
  });
}

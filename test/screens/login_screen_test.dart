import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
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
      serviceFactory: ({required String clientName, storage}) => matrixService,
    );
  });

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
      ],
      child: const MaterialApp(
        home: LoginScreen(),
      ),
    );
  }

  Future<void> tapButton(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  group('LoginScreen', () {
    testWidgets('shows Sign In button and Create an account button',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);
    });

    testWidgets('tapping Create an account navigates to registration screen',
        (tester) async {
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
          'flows': [
            {
              'stages': ['m.login.dummy'],
            },
          ],
          'session': 'sess1',
        }),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tapButton(tester, 'Create an account');
      await tester.pumpAndSettle();

      // Registration screen should be visible
      expect(find.byType(RegistrationScreen), findsOneWidget);
    });

  });
}

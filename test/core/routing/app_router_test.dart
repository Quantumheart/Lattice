import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/auth/screens/registration_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.load();

    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.getLoginFlows()).thenAnswer((_) async => [
          LoginFlow(type: AuthenticationTypes.password),
        ],);
    when(mockClient.request(
      RequestType.POST,
      '/client/v3/register',
      data: anyNamed('data'),
    ),).thenThrow(MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'UIA required',
      'flows': [
        {'stages': ['m.login.registration_token', 'm.login.dummy']},
      ],
      'params': <String, dynamic>{},
      'session': 'test-session',
    }),);

    matrixService = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
    prefs = PreferencesService();
    await prefs.init();
  });

  GoRouter buildMinimalRouter({String initialLocation = '/register'}) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('start'))),
        ),
        GoRoute(
          path: '/register',
          name: Routes.register,
          builder: (context, state) {
            final queryServer = state.uri.queryParameters['server']?.trim();
            final queryToken = state.uri.queryParameters['token']?.trim();
            final homeserver = (state.extra as String?) ??
                (queryServer != null && queryServer.isNotEmpty
                    ? queryServer
                    : null) ??
                context.read<PreferencesService>().defaultHomeserver ??
                AppConfig.instance.defaultHomeserver;
            final token = queryToken != null && queryToken.isNotEmpty
                ? queryToken
                : null;
            return RegistrationScreen(
              key: ValueKey('register|$homeserver|$token'),
              initialHomeserver: homeserver,
              initialToken: token,
            );
          },
        ),
      ],
    );
  }

  Widget buildApp(GoRouter router) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider<PreferencesService>.value(value: prefs),
        ChangeNotifierProvider(
          create: (ctx) =>
              CallService(client: ctx.read<MatrixService>().client),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  group('/register query params', () {
    testWidgets('server + token pre-fill the form', (tester) async {
      final router = buildMinimalRouter(
        initialLocation: '/register?server=matrix.org&token=abc',
      );
      await tester.pumpWidget(buildApp(router));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationScreen), findsOneWidget);

      final hsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(hsField.controller?.text, 'matrix.org');

      final tokenField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(tokenField.controller?.text, 'abc');
    });

    testWidgets('no params falls back to prefs defaultHomeserver',
        (tester) async {
      await prefs.setDefaultHomeserver('prefs.example');
      final router = buildMinimalRouter();
      await tester.pumpWidget(buildApp(router));
      await tester.pumpAndSettle();

      expect(find.byType(RegistrationScreen), findsOneWidget);

      final hsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(hsField.controller?.text, 'prefs.example');
    });

    testWidgets('empty query values fall back to prefs', (tester) async {
      await prefs.setDefaultHomeserver('prefs.example');
      final router = buildMinimalRouter(
        initialLocation: '/register?server=&token=',
      );
      await tester.pumpWidget(buildApp(router));
      await tester.pumpAndSettle();

      final hsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(hsField.controller?.text, 'prefs.example');
    });

    testWidgets('whitespace-only query values fall back to prefs',
        (tester) async {
      await prefs.setDefaultHomeserver('prefs.example');
      final router = buildMinimalRouter(
        initialLocation: '/register?server=%20%20&token=%20',
      );
      await tester.pumpWidget(buildApp(router));
      await tester.pumpAndSettle();

      final hsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(hsField.controller?.text, 'prefs.example');

      final tokenField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(tokenField.controller?.text, '');
    });

    testWidgets('only server query param — token empty', (tester) async {
      final router = buildMinimalRouter(
        initialLocation: '/register?server=matrix.org',
      );
      await tester.pumpWidget(buildApp(router));
      await tester.pumpAndSettle();

      final hsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(hsField.controller?.text, 'matrix.org');

      final tokenField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(tokenField.controller?.text, '');
    });

    testWidgets('only token query param — homeserver falls back to prefs',
        (tester) async {
      await prefs.setDefaultHomeserver('prefs.example');
      final router = buildMinimalRouter(
        initialLocation: '/register?token=solo',
      );
      await tester.pumpWidget(buildApp(router));
      await tester.pumpAndSettle();

      final hsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(hsField.controller?.text, 'prefs.example');

      final tokenField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(tokenField.controller?.text, 'solo');
    });

    testWidgets('URL-encoded token is decoded', (tester) async {
      final router = buildMinimalRouter(
        initialLocation: '/register?server=matrix.org&token=abc%20xyz',
      );
      await tester.pumpWidget(buildApp(router));
      await tester.pumpAndSettle();

      final tokenField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(tokenField.controller?.text, 'abc xyz');
    });

    testWidgets('in-app navigation via router.go pre-fills form',
        (tester) async {
      final router = buildMinimalRouter(initialLocation: '/');
      await tester.pumpWidget(buildApp(router));
      await tester.pumpAndSettle();

      expect(find.text('start'), findsOneWidget);

      router.go('/register?server=matrix.org&token=abc');
      await tester.pumpAndSettle();

      final hsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(hsField.controller?.text, 'matrix.org');

      final tokenField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(tokenField.controller?.text, 'abc');
    });

    testWidgets('re-navigating with different params resets pre-fill',
        (tester) async {
      final router = buildMinimalRouter(
        initialLocation: '/register?server=first.example&token=t1',
      );
      await tester.pumpWidget(buildApp(router));
      await tester.pumpAndSettle();

      var hsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(hsField.controller?.text, 'first.example');

      router.go('/register?server=second.example&token=t2');
      await tester.pumpAndSettle();

      hsField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Homeserver'),
      );
      expect(hsField.controller?.text, 'second.example');

      final tokenField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(tokenField.controller?.text, 't2');
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/auth/screens/registration_screen.dart';
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

  setUp(() {
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

  void stubServerSupportsRegistration({
    List<String> registrationStages = const ['m.login.dummy'],
  }) {
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
        {'stages': registrationStages},
      ],
      'params': <String, dynamic>{},
      'session': 'test-session',
    }),);
  }

  void stubServerRegistrationDisabled() {
    when(mockClient.getLoginFlows()).thenAnswer((_) async => [
          LoginFlow(type: AuthenticationTypes.password),
        ],);
    when(mockClient.request(
      RequestType.POST,
      '/client/v3/register',
      data: anyNamed('data'),
    ),).thenThrow(MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'Registration is disabled',
    }),);
  }

  void stubServerCheckError() {
    when(mockClient.checkHomeserver(any))
        .thenThrow(Exception('Connection refused'));
  }

  Widget buildTestWidget({
    String homeserver = 'matrix.org',
    String? initialToken,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider(
            create: (ctx) =>
                CallService(client: ctx.read<MatrixService>().client),),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
      ],
      child: MaterialApp(
        home: RegistrationScreen(
          initialHomeserver: homeserver,
          initialToken: initialToken,
        ),
      ),
    );
  }

  // ── rendering ──────────────────────────────────────────────

  group('RegistrationScreen', () {
    testWidgets('shows app logo and subtitle', (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Kohera'), findsOneWidget);
      expect(find.text('Create an account on the Matrix network'),
          findsOneWidget,);
    });

    testWidgets('shows homeserver field with initial value', (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget(homeserver: 'custom.server'));
      await tester.pumpAndSettle();

      expect(find.text('custom.server'), findsOneWidget);
    });

    testWidgets('shows username, password, and confirm password fields',
        (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
      expect(
          find.widgetWithText(TextField, 'Confirm password'), findsOneWidget,);
    });

    testWidgets('shows Create Account button when server ready',
        (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('shows sign in link', (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(
          find.text('Already have an account? Sign in'), findsOneWidget,);
    });

    testWidgets('shows registration token field when server requires it',
        (tester) async {
      stubServerSupportsRegistration(
        registrationStages: ['m.login.registration_token', 'm.login.dummy'],
      );
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Registration token'),
          findsOneWidget,);
    });

    testWidgets('hides registration token field when not required',
        (tester) async {
      stubServerSupportsRegistration(
        registrationStages: ['m.login.dummy'],
      );
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(
          find.widgetWithText(TextField, 'Registration token'), findsNothing,);
    });

    // ── server states ──────────────────────────────────────────

    testWidgets('shows loading indicator while checking server',
        (tester) async {
      final completer = Completer<void>();
      when(mockClient.checkHomeserver(any))
          .thenAnswer((_) async {
        await completer.future;
        throw Exception('never completes');
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error when registration is disabled', (tester) async {
      stubServerRegistrationDisabled();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('This server does not support registration'),
          findsOneWidget,);
    });

    testWidgets('shows error when server check fails', (tester) async {
      stubServerCheckError();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Connection refused'), findsOneWidget);
    });

    // ── password visibility toggles ──────────────────────────

    testWidgets('password visibility toggle works', (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final passwordFields = find.byWidgetPredicate(
        (w) => w is TextField && w.obscureText,
      );
      expect(passwordFields, findsNWidgets(2));

      final visibilityButtons = find.byIcon(Icons.visibility_off_outlined);
      expect(visibilityButtons, findsNWidgets(2));

      await tester.tap(visibilityButtons.first);
      await tester.pump();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('confirm password visibility toggle works', (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final visibilityButtons = find.byIcon(Icons.visibility_off_outlined);
      await tester.tap(visibilityButtons.last);
      await tester.pump();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    // ── form validation ──────────────────────────────────────

    testWidgets('shows password mismatch error on submit', (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Username'), 'alice',);
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password123',);
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm password'), 'different123',);

      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('clears password mismatch error when typing', (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Username'), 'alice',);
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password123',);
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm password'), 'different123',);

      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm password'), 'password123',);
      await tester.pump();

      expect(find.text('Passwords do not match'), findsNothing);
    });

    testWidgets('submit shows registering state when passwords match',
        (tester) async {
      stubServerSupportsRegistration();

      final registerCompleter = Completer<RegisterResponse>();
      when(mockClient.register(
        username: anyNamed('username'),
        password: anyNamed('password'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
        auth: anyNamed('auth'),
      ),).thenAnswer((_) => registerCompleter.future);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Username'), 'alice',);
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password123',);
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm password'), 'password123',);

      await tester.tap(find.text('Create Account'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('Create Account button disabled when form fields disabled',
        (tester) async {
      stubServerRegistrationDisabled();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.widgetWithText(
        FilledButton,
        'Create Account',
      ),);
      expect(button.onPressed, isNull);
    });

    testWidgets('Create Account button enabled when server ready',
        (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.widgetWithText(
        FilledButton,
        'Create Account',
      ),);
      expect(button.onPressed, isNotNull);
    });

    // ── keyboard submit ──────────────────────────────────────

    testWidgets('confirm password field submit triggers form submit',
        (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Username'), 'alice',);
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password123',);
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm password'), 'different',);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    // ── homeserver debounce ──────────────────────────────────

    testWidgets('changing homeserver re-checks server after debounce',
        (tester) async {
      stubServerSupportsRegistration();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      stubServerRegistrationDisabled();

      await tester.enterText(
          find.widgetWithText(TextField, 'matrix.org'), 'other.server',);

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      expect(find.text('This server does not support registration'),
          findsOneWidget,);
    });

    // ── initialToken ──────────────────────────────────────────

    testWidgets('initialToken pre-fills the token field', (tester) async {
      stubServerSupportsRegistration(
        registrationStages: ['m.login.registration_token', 'm.login.dummy'],
      );
      await tester.pumpWidget(buildTestWidget(initialToken: 'abc123'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(field.controller?.text, 'abc123');
    });

    testWidgets('initialToken null leaves the token field empty',
        (tester) async {
      stubServerSupportsRegistration(
        registrationStages: ['m.login.registration_token', 'm.login.dummy'],
      );
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(field.controller?.text, '');
    });

    testWidgets('seeded token field remains editable', (tester) async {
      stubServerSupportsRegistration(
        registrationStages: ['m.login.registration_token', 'm.login.dummy'],
      );
      await tester.pumpWidget(buildTestWidget(initialToken: 'abc123'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Registration token'),
        'overwrite',
      );
      await tester.pump();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Registration token'),
      );
      expect(field.controller?.text, 'overwrite');
    });
  });
}

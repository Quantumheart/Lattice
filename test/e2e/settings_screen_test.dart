import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/settings/screens/settings_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service_test.mocks.dart' show MockFlutterSecureStorage;
import 'settings_screen_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])

// ── Constants ─────────────────────────────────────────────────────────

const _myUserId = '@alice:matrix.org';
const _homeserver = 'https://matrix.org';

// ── Helpers ───────────────────────────────────────────────────────────

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

void stubProfile(
  MockClient mockClient, {
  String? displayName,
  Uri? avatarUrl,
}) {
  when(mockClient.fetchOwnProfile()).thenAnswer(
    (_) async => Profile(
      userId: _myUserId,
      displayName: displayName,
      avatarUrl: avatarUrl,
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService matrixService;
  late ClientManager clientManager;
  late CachedStreamController<SyncUpdate> syncController;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    syncController = CachedStreamController<SyncUpdate>();

    when(mockClient.userID).thenReturn(_myUserId);
    when(mockClient.homeserver).thenReturn(Uri.parse(_homeserver));
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(syncController);
    when(mockClient.encryption).thenReturn(null);
    when(mockClient.encryptionEnabled).thenReturn(false);
    when(mockClient.onLoginStateChanged)
        .thenReturn(CachedStreamController<LoginState>());
    when(mockClient.onUiaRequest)
        .thenReturn(CachedStreamController<UiaRequest<dynamic>>());

    stubProfile(mockClient, displayName: 'Alice');

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

  // ── Test app builder ──────────────────────────────────────────────

  Widget buildSettingsApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: matrixService),
        ChangeNotifierProvider(create: (ctx) => CallService(client: ctx.read<MatrixService>().client)),
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
        ChangeNotifierProvider(create: (_) => PreferencesService()),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  Future<void> scrollToBottom(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
  }

  // ── Group 1: Profile Display ──────────────────────────────────

  group('Settings screen — profile display', () {
    testWidgets('displays user ID and homeserver', (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();

      expect(find.text(_myUserId), findsOneWidget);
      expect(find.text(_homeserver), findsOneWidget);
    });

    testWidgets('displays display name from profile', (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsAtLeast(1));
    });
  });

  // ── Group 2: Edit Display Name ─────────────────────────────────

  group('Settings screen — edit display name', () {
    testWidgets('edit display name and save', (tester) async {
      when(mockClient.setProfileField(any, any, any))
          .thenAnswer((_) async => <String, Object?>{});

      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();

      final textField = find.widgetWithText(TextField, 'Display name');
      await tester.enterText(textField, 'Bob');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save display name'));
      await tester.pumpAndSettle();

      verify(
        mockClient.setProfileField(
          _myUserId,
          'displayname',
          {'displayname': 'Bob'},
        ),
      ).called(1);
    });
  });

  // ── Group 3: Chat Backup Status ────────────────────────────────

  group('Settings screen — chat backup status', () {
    testWidgets('shows backup status tile', (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();
      await scrollToBottom(tester);

      expect(find.text('Chat backup'), findsOneWidget);
    });
  });

  // ── Group 4: Logout ─────────────────────────────────────────────

  group('Settings screen — logout', () {
    testWidgets('logout confirmation dialog appears', (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();
      await scrollToBottom(tester);

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsOneWidget);
    });

    testWidgets('logout with missing backup shows warning',
        (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();
      await scrollToBottom(tester);

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('encryption keys are not backed up'),
        findsOneWidget,
      );
      expect(find.text('Set up backup first'), findsOneWidget);
    });

    testWidgets('cancel logout closes dialog', (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();
      await scrollToBottom(tester);

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsNothing);
    });
  });

  // ── Group 5: Preferences ──────────────────────────────────────

  group('Settings screen — preferences', () {
    testWidgets('preference sections are displayed', (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();

      expect(find.text('PREFERENCES'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Message density'), findsOneWidget);
    });

    testWidgets('security section shows devices and backup tiles',
        (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();
      await scrollToBottom(tester);

      expect(find.text('SECURITY'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('Chat backup'), findsOneWidget);
    });
  });

  // ── Group 6: Add Account ──────────────────────────────────────

  group('Settings screen — add account', () {
    testWidgets('add account button is visible', (tester) async {
      await tester.pumpWidget(buildSettingsApp());
      await tester.pumpAndSettle();

      expect(find.text('Add account'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/settings/screens/voice_video_settings_screen.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_video_settings_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
])
void main() {
  late MockClient mockClient;
  late PreferencesService prefs;
  late CallService callService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);

    mockClient = MockClient();
    when(mockClient.userID).thenReturn('@alice:matrix.org');
    when(mockClient.homeserver).thenReturn(Uri.parse('https://matrix.org'));
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync)
        .thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.encryption).thenReturn(null);
    when(mockClient.encryptionEnabled).thenReturn(false);
    when(mockClient.onLoginStateChanged)
        .thenReturn(CachedStreamController<LoginState>());
    when(mockClient.onUiaRequest)
        .thenReturn(CachedStreamController<UiaRequest<dynamic>>());

    callService = CallService(client: mockClient);
  });

  Widget buildTestApp({bool callingAvailable = true}) {
    if (callingAvailable) {
      callService.cachedLivekitServiceUrlForTest = 'https://lk.example.com';
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PreferencesService>.value(value: prefs),
        ChangeNotifierProvider<CallService>.value(value: callService),
      ],
      child: const MaterialApp(home: VoiceVideoSettingsScreen()),
    );
  }

  group('screen rendering', () {
    testWidgets('renders calling status section', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('CALLING STATUS'), findsOneWidget);
      expect(find.text('Voice & video calls'), findsOneWidget);
      expect(find.text('Supported by your homeserver'), findsOneWidget);
    });

    testWidgets('renders microphone section', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('MICROPHONE'), findsOneWidget);
      expect(find.text('Auto-mute when joining'), findsOneWidget);
      expect(find.text('Noise suppression'), findsOneWidget);
      expect(find.text('Echo cancellation'), findsOneWidget);
    });

    testWidgets('renders audio processing toggles', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.text('Auto gain control'), findsOneWidget);
      expect(find.text('Voice isolation'), findsOneWidget);
      expect(find.text('Typing noise detection'), findsOneWidget);
    });

    testWidgets('renders audio quality section', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('AUDIO QUALITY'), findsOneWidget);
    });

    testWidgets('renders speaker section', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(find.text('SPEAKER'), findsOneWidget);
    });

    testWidgets('volume sliders show percentage', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('100%'), findsAtLeast(1));
    });
  });

  group('preference toggles', () {
    testWidgets('toggling auto-mute updates preference', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(prefs.autoMuteOnJoin, isFalse);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Auto-mute when joining'));
      await tester.pumpAndSettle();
      expect(prefs.autoMuteOnJoin, isTrue);
    });

    testWidgets('toggling noise suppression updates preference', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(prefs.noiseSuppression, isTrue);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Noise suppression'));
      await tester.pumpAndSettle();
      expect(prefs.noiseSuppression, isFalse);
    });

    testWidgets('toggling echo cancellation updates preference', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(prefs.echoCancellation, isTrue);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Echo cancellation'));
      await tester.pumpAndSettle();
      expect(prefs.echoCancellation, isFalse);
    });
  });

  group('calling unavailable', () {
    testWidgets('shows not supported message', (tester) async {
      await tester.pumpWidget(buildTestApp(callingAvailable: false));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('does not support calling'),
        findsOneWidget,
      );
    });
  });
}

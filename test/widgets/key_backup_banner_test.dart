import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/features/e2ee/widgets/key_backup_banner.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([MockSpec<ChatBackupService>()])
import 'key_backup_banner_test.mocks.dart';

void main() {
  late MockChatBackupService mockChatBackup;

  setUp(() {
    mockChatBackup = MockChatBackupService();
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: ChangeNotifierProvider<ChatBackupService>.value(
        value: mockChatBackup,
        child: const Scaffold(body: KeyBackupBanner()),
      ),
    );
  }

  group('KeyBackupBanner', () {
    testWidgets('hidden when chatBackupNeeded is null', (tester) async {
      when(mockChatBackup.chatBackupNeeded).thenReturn(null);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);
    });

    testWidgets('visible when chatBackupNeeded is true', (tester) async {
      when(mockChatBackup.chatBackupNeeded).thenReturn(true);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsOneWidget);
      expect(
        find.text(
          'Without key backup, you may lose message history '
          'and some features will not work',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Set up'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byIcon(Icons.shield_outlined),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });

    testWidgets('hidden when chatBackupNeeded is false', (tester) async {
      when(mockChatBackup.chatBackupNeeded).thenReturn(false);
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);
    });

    testWidgets('disappears when backup status changes to enabled',
        (tester) async {
      final fake = _FakeChatBackupService(chatBackupNeeded: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ChatBackupService>.value(
            value: fake,
            child: const Scaffold(body: KeyBackupBanner()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsOneWidget);

      fake.chatBackupNeeded = false;
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);
    });

    testWidgets('appears when backup status changes to needed',
        (tester) async {
      final fake = _FakeChatBackupService(chatBackupNeeded: false);
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ChatBackupService>.value(
            value: fake,
            child: const Scaffold(body: KeyBackupBanner()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsNothing);

      fake.chatBackupNeeded = true;
      await tester.pumpAndSettle();

      expect(find.text('Protect your messages'), findsOneWidget);
    });
  });
}

class _FakeChatBackupService extends ChangeNotifier
    implements ChatBackupService {
  bool? _chatBackupNeeded;

  _FakeChatBackupService({required bool? chatBackupNeeded})
      : _chatBackupNeeded = chatBackupNeeded;

  @override
  bool? get chatBackupNeeded => _chatBackupNeeded;
  set chatBackupNeeded(bool? value) {
    _chatBackupNeeded = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

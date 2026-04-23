import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/features/e2ee/widgets/verification_request_listener.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'key_verification_dialog_test.dart' show FakeKeyVerification;

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<ChatBackupService>(),
])
import 'verification_request_listener_test.mocks.dart';

class _FakeVerification extends FakeKeyVerification {
  _FakeVerification({required String userId}) : _userId = userId;

  final String _userId;

  @override
  String get userId => _userId;
}

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;
  late MockChatBackupService mockChatBackup;
  late CachedStreamController<KeyVerification> verificationStream;

  const selfUserId = '@self:example.com';
  const otherUserId = '@other:example.com';

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    mockChatBackup = MockChatBackupService();
    verificationStream = CachedStreamController<KeyVerification>();

    when(mockClient.userID).thenReturn(selfUserId);
    when(mockClient.onKeyVerificationRequest).thenReturn(verificationStream);
    when(mockMatrix.client).thenReturn(mockClient);
    when(mockMatrix.chatBackup).thenReturn(mockChatBackup);
    when(mockChatBackup.runKeyRecovery(ssssKey: anyNamed('ssssKey')))
        .thenAnswer((_) => Future<void>.value());
    when(mockChatBackup.checkChatBackupStatus())
        .thenAnswer((_) => Future<void>.value());
  });

  Future<GoRouter> pumpListener(WidgetTester tester) async {
    late GoRouter router;
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MatrixService>.value(
        value: mockMatrix,
        child: VerificationRequestListener(
          router: router,
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pump();
    return router;
  }

  testWidgets(
      'self verification confirmed via Done button triggers runKeyRecovery',
      (tester) async {
    await pumpListener(tester);

    final verification = _FakeVerification(userId: selfUserId);
    verificationStream.add(verification);
    await tester.pump();

    verification.simulateStateChange(KeyVerificationState.done);
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    verify(mockChatBackup.runKeyRecovery(ssssKey: anyNamed('ssssKey')))
        .called(1);
  });

  testWidgets(
      'self verification confirmed refreshes chat backup status '
      '(regression for #309)', (tester) async {
    await pumpListener(tester);

    final verification = _FakeVerification(userId: selfUserId);
    verificationStream.add(verification);
    await tester.pump();

    verification.simulateStateChange(KeyVerificationState.done);
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    verify(mockChatBackup.checkChatBackupStatus()).called(1);
  });

  testWidgets(
      'cross-user verification confirmed does not refresh chat backup status',
      (tester) async {
    await pumpListener(tester);

    final verification = _FakeVerification(userId: otherUserId);
    verificationStream.add(verification);
    await tester.pump();

    verification.simulateStateChange(KeyVerificationState.done);
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    verifyNever(mockChatBackup.checkChatBackupStatus());
  });

  testWidgets('self verification cancelled does not trigger runKeyRecovery',
      (tester) async {
    await pumpListener(tester);

    final verification = _FakeVerification(userId: selfUserId);
    verificationStream.add(verification);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    verifyNever(
      mockChatBackup.runKeyRecovery(ssssKey: anyNamed('ssssKey')),
    );
  });

  testWidgets('cross-user verification confirmed does not trigger runKeyRecovery',
      (tester) async {
    await pumpListener(tester);

    final verification = _FakeVerification(userId: otherUserId);
    verificationStream.add(verification);
    await tester.pump();

    verification.simulateStateChange(KeyVerificationState.done);
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    verifyNever(
      mockChatBackup.runKeyRecovery(ssssKey: anyNamed('ssssKey')),
    );
  });
}

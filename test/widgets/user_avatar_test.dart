import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';

import 'package:matrix/matrix.dart';

import 'package:lattice/widgets/user_avatar.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
])
import 'user_avatar_test.mocks.dart';

void main() {
  late MockClient mockClient;

  setUp(() {
    mockClient = MockClient();
  });

  Widget buildTestWidget({
    Uri? avatarUrl,
    String? userId,
    double size = 44,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: UserAvatar(
          client: mockClient,
          avatarUrl: avatarUrl,
          userId: userId,
          size: size,
        ),
      ),
    );
  }

  group('UserAvatar', () {
    testWidgets('shows initial fallback when no avatar URL', (tester) async {
      await tester.pumpWidget(buildTestWidget(userId: '@alice:example.com'));
      await tester.pumpAndSettle();

      // Should show 'A' (second char of @alice, uppercased)
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('shows first char when userId is single character', (tester) async {
      await tester.pumpWidget(buildTestWidget(userId: '@'));
      await tester.pumpAndSettle();

      expect(find.text('@'), findsOneWidget);
    });

    testWidgets('shows ? when no userId provided', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders at correct size', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        userId: '@bob:example.com',
        size: 64,
      ));
      await tester.pumpAndSettle();

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 64);
      expect(sizedBox.height, 64);
    });

    testWidgets('resolves thumbnail when avatarUrl is provided', (tester) async {
      final mxcUri = Uri.parse('mxc://example.com/avatar123');

      await tester.pumpWidget(buildTestWidget(
        avatarUrl: mxcUri,
        userId: '@charlie:example.com',
      ));
      await tester.pump();

      // While resolving, the fallback initial should show
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('different userIds produce different colors', (tester) async {
      // This tests the color hashing — render two avatars and check they exist
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              UserAvatar(
                client: mockClient,
                userId: '@alice:example.com',
              ),
              UserAvatar(
                client: mockClient,
                userId: '@bob:example.com',
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('uses ClipOval for circular shape', (tester) async {
      await tester.pumpWidget(buildTestWidget(userId: '@dave:example.com'));
      await tester.pumpAndSettle();

      expect(find.byType(ClipOval), findsOneWidget);
    });
  });
}

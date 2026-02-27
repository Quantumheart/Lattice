import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/widgets/chat/read_receipts.dart';
import 'package:lattice/widgets/user_avatar.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<User>(),
  MockSpec<Client>(),
])
import 'read_receipts_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

MockUser _makeUser(String id, String? displayName, {Uri? avatarUrl}) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  when(user.avatarUrl).thenReturn(avatarUrl);
  return user;
}

MockRoom _makeRoom({
  required Map<String, LatestReceiptStateData> globalOtherUsers,
  Map<String, LatestReceiptStateData>? mainThreadOtherUsers,
  required Map<String, MockUser> userMap,
}) {
  final room = MockRoom();

  final global = LatestReceiptStateForTimeline(
    ownPrivate: null,
    ownPublic: null,
    latestOwnReceipt: null,
    otherUsers: globalOtherUsers,
  );

  LatestReceiptStateForTimeline? mainThread;
  if (mainThreadOtherUsers != null) {
    mainThread = LatestReceiptStateForTimeline(
      ownPrivate: null,
      ownPublic: null,
      latestOwnReceipt: null,
      otherUsers: mainThreadOtherUsers,
    );
  }

  when(room.receiptState).thenReturn(LatestReceiptState(
    global: global,
    mainThread: mainThread,
  ));

  for (final entry in userMap.entries) {
    when(room.unsafeGetUserFromMemoryOrFallback(entry.key))
        .thenReturn(entry.value);
  }

  return room;
}

Widget _wrapRow(List<Receipt> receipts, Client client, {bool isMe = true}) {
  return MaterialApp(
    home: Scaffold(
      body: ReadReceiptsRow(
        receipts: receipts,
        client: client,
        isMe: isMe,
        senderAvatarOffset: 36,
      ),
    ),
  );
}

// ── Tests ────────────────────────────────────────────────────

void main() {
  group('buildReceiptMap', () {
    test('maps receipts by eventId and excludes own user', () {
      final alice = _makeUser('@alice:example.com', 'Alice');
      final bob = _makeUser('@bob:example.com', 'Bob');

      final room = _makeRoom(
        globalOtherUsers: {
          '@alice:example.com': LatestReceiptStateData('\$evt1', 1000),
          '@bob:example.com': LatestReceiptStateData('\$evt1', 2000),
          '@me:example.com': LatestReceiptStateData('\$evt2', 3000),
        },
        userMap: {
          '@alice:example.com': alice,
          '@bob:example.com': bob,
          '@me:example.com': _makeUser('@me:example.com', 'Me'),
        },
      );

      final map = buildReceiptMap(room, '@me:example.com');

      expect(map.containsKey('\$evt1'), isTrue);
      expect(map['\$evt1']!.length, 2);
      expect(map['\$evt1']!.map((r) => r.user.id),
          containsAll(['@alice:example.com', '@bob:example.com']));

      // Own user should not appear
      expect(
        map.values.expand((l) => l).any((r) => r.user.id == '@me:example.com'),
        isFalse,
      );
    });

    test('includes mainThread receipts without duplicating users', () {
      final alice = _makeUser('@alice:example.com', 'Alice');

      final room = _makeRoom(
        globalOtherUsers: {
          '@alice:example.com': LatestReceiptStateData('\$evt1', 1000),
        },
        mainThreadOtherUsers: {
          '@alice:example.com': LatestReceiptStateData('\$evt2', 2000),
        },
        userMap: {
          '@alice:example.com': alice,
        },
      );

      final map = buildReceiptMap(room, '@me:example.com');

      // Alice should only appear once (from global, since it's processed first)
      final allReceipts = map.values.expand((l) => l).toList();
      expect(
        allReceipts.where((r) => r.user.id == '@alice:example.com').length,
        1,
      );
    });

    test('returns empty map for room with no receipts', () {
      final room = _makeRoom(
        globalOtherUsers: {},
        userMap: {},
      );

      final map = buildReceiptMap(room, '@me:example.com');
      expect(map, isEmpty);
    });
  });

  group('ReadReceiptsRow', () {
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient();
      when(mockClient.userID).thenReturn('@me:example.com');
    });

    testWidgets('renders SizedBox.shrink for empty receipts', (tester) async {
      await tester.pumpWidget(_wrapRow([], mockClient));

      // Should find a SizedBox with zero dimensions (shrink)
      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 0);
      expect(sizedBox.height, 0);
    });

    testWidgets('renders correct number of avatars for 2 receipts',
        (tester) async {
      final receipts = [
        Receipt(
          _makeUser('@alice:example.com', 'Alice'),
          DateTime(2024, 1, 1, 12, 0),
        ),
        Receipt(
          _makeUser('@bob:example.com', 'Bob'),
          DateTime(2024, 1, 1, 12, 5),
        ),
      ];

      await tester.pumpWidget(_wrapRow(receipts, mockClient));
      await tester.pump();

      expect(find.byType(UserAvatar), findsNWidgets(2));
      // Should not show overflow badge
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('shows +N badge when more than 3 receipts', (tester) async {
      final receipts = List.generate(
        5,
        (i) => Receipt(
          _makeUser('@user$i:example.com', 'User $i'),
          DateTime(2024, 1, 1, 12, i),
        ),
      );

      await tester.pumpWidget(_wrapRow(receipts, mockClient));
      await tester.pump();

      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('tap opens readers bottom sheet', (tester) async {
      final receipts = [
        Receipt(
          _makeUser('@alice:example.com', 'Alice'),
          DateTime(2024, 1, 1, 14, 30),
        ),
      ];

      await tester.pumpWidget(_wrapRow(receipts, mockClient));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Bottom sheet should show "Read by 1"
      expect(find.text('Read by 1'), findsOneWidget);
      // Should show the user's name
      expect(find.text('Alice'), findsOneWidget);
      // Should show the time (locale-aware: US English default)
      expect(find.text('2:30 PM'), findsOneWidget);
    });

    testWidgets('bottom sheet shows multiple readers', (tester) async {
      final receipts = [
        Receipt(
          _makeUser('@alice:example.com', 'Alice'),
          DateTime(2024, 1, 1, 14, 30),
        ),
        Receipt(
          _makeUser('@bob:example.com', 'Bob'),
          DateTime(2024, 1, 1, 15, 45),
        ),
      ];

      await tester.pumpWidget(_wrapRow(receipts, mockClient));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.text('Read by 2'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('falls back to user ID when displayName is null',
        (tester) async {
      final receipts = [
        Receipt(
          _makeUser('@anon:example.com', null),
          DateTime(2024, 1, 1, 10, 0),
        ),
      ];

      await tester.pumpWidget(_wrapRow(receipts, mockClient));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.text('@anon:example.com'), findsOneWidget);
    });
  });
}

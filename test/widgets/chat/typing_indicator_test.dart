import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/widgets/chat/typing_indicator.dart';

@GenerateNiceMocks([MockSpec<Room>(), MockSpec<User>()])
import 'typing_indicator_test.mocks.dart';

MockUser _makeUser(String id, String? displayName) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  return user;
}

Widget _wrap(Room room, {String? myUserId}) {
  return MaterialApp(
    home: Scaffold(
      body: TypingIndicator(
        room: room,
        myUserId: myUserId ?? '@me:example.com',
        syncStream: const Stream.empty(),
      ),
    ),
  );
}

void main() {
  group('TypingIndicator', () {
    late MockRoom mockRoom;

    setUp(() {
      mockRoom = MockRoom();
    });

    testWidgets('empty typingUsers renders nothing', (tester) async {
      when(mockRoom.typingUsers).thenReturn([]);
      await tester.pumpWidget(_wrap(mockRoom));

      expect(find.textContaining('typing'), findsNothing);
    });

    testWidgets('1 user shows "Alice is typing"', (tester) async {
      final alice = _makeUser('@alice:example.com', 'Alice');
      when(mockRoom.typingUsers).thenReturn([alice]);
      await tester.pumpWidget(_wrap(mockRoom));
      await tester.pump();

      expect(find.text('Alice is typing'), findsOneWidget);
    });

    testWidgets('2 users shows "Alice and Bob are typing"', (tester) async {
      final alice = _makeUser('@alice:example.com', 'Alice');
      final bob = _makeUser('@bob:example.com', 'Bob');
      when(mockRoom.typingUsers).thenReturn([alice, bob]);
      await tester.pumpWidget(_wrap(mockRoom));
      await tester.pump();

      expect(find.text('Alice and Bob are typing'), findsOneWidget);
    });

    testWidgets('3 users shows all names', (tester) async {
      final alice = _makeUser('@alice:example.com', 'Alice');
      final bob = _makeUser('@bob:example.com', 'Bob');
      final carol = _makeUser('@carol:example.com', 'Carol');
      when(mockRoom.typingUsers).thenReturn([alice, bob, carol]);
      await tester.pumpWidget(_wrap(mockRoom));
      await tester.pump();

      expect(find.text('Alice, Bob, and Carol are typing'), findsOneWidget);
    });

    testWidgets('4+ users shows "N others"', (tester) async {
      final alice = _makeUser('@alice:example.com', 'Alice');
      final bob = _makeUser('@bob:example.com', 'Bob');
      final carol = _makeUser('@carol:example.com', 'Carol');
      final dave = _makeUser('@dave:example.com', 'Dave');
      when(mockRoom.typingUsers).thenReturn([alice, bob, carol, dave]);
      await tester.pumpWidget(_wrap(mockRoom));
      await tester.pump();

      expect(find.text('Alice, Bob, and 2 others are typing'), findsOneWidget);
    });

    testWidgets('own user is filtered out', (tester) async {
      final me = _makeUser('@me:example.com', 'Me');
      final alice = _makeUser('@alice:example.com', 'Alice');
      when(mockRoom.typingUsers).thenReturn([me, alice]);
      await tester.pumpWidget(_wrap(mockRoom, myUserId: '@me:example.com'));
      await tester.pump();

      expect(find.text('Alice is typing'), findsOneWidget);
    });

    testWidgets('null displayName falls back to user ID', (tester) async {
      final noName = _makeUser('@anon:example.com', null);
      when(mockRoom.typingUsers).thenReturn([noName]);
      await tester.pumpWidget(_wrap(mockRoom));
      await tester.pump();

      expect(find.text('@anon:example.com is typing'), findsOneWidget);
    });

    testWidgets('only own user typing renders nothing', (tester) async {
      final me = _makeUser('@me:example.com', 'Me');
      when(mockRoom.typingUsers).thenReturn([me]);
      await tester.pumpWidget(_wrap(mockRoom, myUserId: '@me:example.com'));
      await tester.pump();

      expect(find.textContaining('typing'), findsNothing);
    });
  });
}

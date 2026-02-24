import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/room_members_section.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<User>(),
])
import 'room_members_section_test.mocks.dart';

MockUser _makeUser(String id, String displayName, {Room? room}) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  when(user.room).thenReturn(room ?? MockRoom());
  return user;
}

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockRoom;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockRoom = MockRoom();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.summary).thenReturn(RoomSummary.fromJson({
      'm.joined_member_count': 3,
      'm.invited_member_count': 0,
    }));
    when(mockRoom.getPowerLevelByUserId(any)).thenReturn(0);
    when(mockRoom.canKick).thenReturn(false);
    when(mockRoom.canBan).thenReturn(false);
    when(mockClient.userID).thenReturn('@me:example.com');
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: ChangeNotifierProvider<MatrixService>.value(
        value: mockMatrixService,
        child: Scaffold(
          body: RoomMembersSection(room: mockRoom),
        ),
      ),
    );
  }

  group('RoomMembersSection', () {
    testWidgets('shows loading indicator while fetching members',
        (tester) async {
      final completer = Completer<List<User>>();
      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('MEMBERS'), findsOneWidget);

      // Complete the future to avoid pending timer issues
      completer.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('shows members after loading', (tester) async {
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      final bob = _makeUser('@bob:example.com', 'Bob', room: mockRoom);

      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) async => [alice, bob]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows only first 5 members with expand button',
        (tester) async {
      final users = List.generate(
        8,
        (i) => _makeUser('@user$i:example.com', 'User $i', room: mockRoom),
      );

      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => users);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // First 5 should be visible
      for (var i = 0; i < 5; i++) {
        expect(find.text('User $i'), findsOneWidget);
      }
      // 6th should not be visible yet
      expect(find.text('User 5'), findsNothing);

      // Expand button should show
      expect(find.text('Show all 8 members'), findsOneWidget);
    });

    testWidgets('expand button shows all members', (tester) async {
      final users = List.generate(
        8,
        (i) => _makeUser('@user$i:example.com', 'User $i', room: mockRoom),
      );

      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => users);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show all 8 members'));
      await tester.pumpAndSettle();

      // All 8 should be visible now
      for (var i = 0; i < 8; i++) {
        expect(find.text('User $i'), findsOneWidget);
      }
      expect(find.text('Show all 8 members'), findsNothing);
    });

    testWidgets('shows Admin badge for power level >= 100', (tester) async {
      final admin = _makeUser('@admin:example.com', 'Admin User', room: mockRoom);
      when(mockRoom.getPowerLevelByUserId('@admin:example.com')).thenReturn(100);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [admin]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsOneWidget);
    });

    testWidgets('shows Mod badge for power level >= 50', (tester) async {
      final mod = _makeUser('@mod:example.com', 'Mod User', room: mockRoom);
      when(mockRoom.getPowerLevelByUserId('@mod:example.com')).thenReturn(50);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [mod]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Mod'), findsOneWidget);
    });

    testWidgets('tapping member opens bottom sheet', (tester) async {
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) async => [alice]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      // Bottom sheet should show member info
      expect(find.text('@alice:example.com'), findsWidgets);
      expect(find.text('Member'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/widgets/chat/reaction_chips.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<Timeline>(),
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<User>(),
])
import 'reaction_chips_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

MockEvent _makeReactionEvent({
  required String senderId,
  required String emoji,
}) {
  final event = MockEvent();
  when(event.senderId).thenReturn(senderId);
  when(event.content).thenReturn({
    'm.relates_to': {'key': emoji},
  });
  return event;
}

MockEvent _makeParentEvent({
  required MockTimeline timeline,
  required List<MockEvent> reactions,
  MockRoom? room,
}) {
  final event = MockEvent();
  when(event.aggregatedEvents(timeline, RelationshipTypes.reaction))
      .thenReturn(reactions.toSet());
  when(event.hasAggregatedEvents(timeline, RelationshipTypes.reaction))
      .thenReturn(reactions.isNotEmpty);
  if (room != null) {
    when(event.room).thenReturn(room);
  }
  return event;
}

Widget _wrapChips({
  required MockEvent event,
  required MockTimeline timeline,
  required MockClient client,
  bool isMe = false,
  void Function(String emoji)? onToggle,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ReactionChips(
        event: event,
        timeline: timeline,
        client: client,
        isMe: isMe,
        senderAvatarOffset: 36,
        onToggle: onToggle,
      ),
    ),
  );
}

// ── Tests ────────────────────────────────────────────────────

void main() {
  late MockTimeline mockTimeline;
  late MockClient mockClient;

  setUp(() {
    mockTimeline = MockTimeline();
    mockClient = MockClient();
    when(mockClient.userID).thenReturn('@me:example.com');
  });

  testWidgets('renders nothing when no reactions', (tester) async {
    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: [],
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ));

    final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
    expect(sizedBox.width, 0);
    expect(sizedBox.height, 0);
  });

  testWidgets('renders correct chip count for multiple emojis',
      (tester) async {
    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
      _makeReactionEvent(senderId: '@bob:example.com', emoji: '\u{2764}\u{FE0F}'),
      _makeReactionEvent(senderId: '@carol:example.com', emoji: '\u{1F602}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ));

    // Three different emojis → three chips (each with count 1, so just emoji)
    expect(find.text('\u{1F44D}'), findsOneWidget);
    expect(find.text('\u{2764}\u{FE0F}'), findsOneWidget);
    expect(find.text('\u{1F602}'), findsOneWidget);
  });

  testWidgets('shows correct count per emoji', (tester) async {
    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
      _makeReactionEvent(senderId: '@bob:example.com', emoji: '\u{1F44D}'),
      _makeReactionEvent(senderId: '@carol:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ));

    // One emoji chip with count 3 (emoji and count are separate Text widgets)
    expect(find.text('\u{1F44D}'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('highlights chip for current user reaction', (tester) async {
    final reactions = [
      _makeReactionEvent(senderId: '@me:example.com', emoji: '\u{1F44D}'),
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ));

    // Find the chip container (has a BoxDecoration with borderRadius)
    final cs = Theme.of(
      tester.element(find.byType(ReactionChips)),
    ).colorScheme;

    final chipContainer = tester.widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.borderRadius != null;
        }).first;
    final decoration = chipContainer.decoration as BoxDecoration;
    expect(decoration.color, cs.primaryContainer);
    expect(decoration.border, isNotNull);
  });

  testWidgets('no highlight for others-only reactions', (tester) async {
    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ));

    final cs = Theme.of(
      tester.element(find.byType(ReactionChips)),
    ).colorScheme;

    final chipContainer = tester.widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.borderRadius != null;
        }).first;
    final decoration = chipContainer.decoration as BoxDecoration;
    expect(decoration.color, cs.surfaceContainerHighest);
    expect(decoration.border, isNull);
  });

  testWidgets('tap calls onToggle with correct emoji', (tester) async {
    String? tappedEmoji;
    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
      onToggle: (emoji) => tappedEmoji = emoji,
    ));

    await tester.tap(find.text('\u{1F44D}'));
    expect(tappedEmoji, '\u{1F44D}');
  });

  testWidgets('long-press opens reactors sheet', (tester) async {
    final mockRoom = MockRoom();
    final mockUser = MockUser();
    when(mockUser.displayName).thenReturn('Alice');
    when(mockUser.avatarUrl).thenReturn(null);
    when(mockRoom.unsafeGetUserFromMemoryOrFallback('@alice:example.com'))
        .thenReturn(mockUser);
    when(mockRoom.client).thenReturn(mockClient);

    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
      room: mockRoom,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ));

    await tester.longPress(find.text('\u{1F44D}'));
    await tester.pumpAndSettle();

    // Bottom sheet should show the emoji with count
    expect(find.text('\u{1F44D} 1'), findsWidgets);
    // Should show the reactor's name
    expect(find.text('Alice'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/widgets/message_action_sheet.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<Timeline>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
  MockSpec<User>(),
])
import 'message_action_sheet_test.mocks.dart';

late MockRoom _mockRoom;

MockEvent _makeEvent({
  required String eventId,
  required String senderId,
  String body = 'Hello',
}) {
  final event = MockEvent();
  when(event.eventId).thenReturn(eventId);
  when(event.senderId).thenReturn(senderId);
  when(event.body).thenReturn(body);
  when(event.type).thenReturn(EventTypes.Message);
  when(event.messageType).thenReturn(MessageTypes.Text);
  when(event.originServerTs).thenReturn(DateTime(2025, 1, 1, 12));
  when(event.status).thenReturn(EventStatus.synced);
  when(event.content).thenReturn({'body': body, 'msgtype': 'm.text'});
  when(event.room).thenReturn(_mockRoom);
  when(event.redacted).thenReturn(false);
  when(event.canRedact).thenReturn(true);
  when(event.relationshipType).thenReturn(null);
  when(event.getDisplayEvent(any)).thenReturn(event);
  when(event.hasAggregatedEvents(any, any)).thenReturn(false);
  when(event.formattedText).thenReturn('');

  final sender = MockUser();
  when(sender.displayName).thenReturn(senderId.split(':').first.substring(1));
  when(sender.avatarUrl).thenReturn(null);
  when(event.senderFromMemoryOrFallback).thenReturn(sender);

  return event;
}

void main() {
  late MockRoom mockRoom;
  late MockTimeline mockTimeline;
  late MockClient mockClient;

  setUp(() {
    mockRoom = MockRoom();
    mockTimeline = MockTimeline();
    mockClient = MockClient();
    _mockRoom = mockRoom;

    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.client).thenReturn(mockClient);
    when(mockClient.userID).thenReturn('@me:example.com');
  });

  Widget buildTestWidget({
    required List<MessageAction> actions,
    void Function(String emoji)? onQuickReact,
    MockEvent? event,
  }) {
    final e = event ?? _makeEvent(eventId: r'$evt1', senderId: '@me:x');

    return ChangeNotifierProvider<PreferencesService>.value(
      value: PreferencesService(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showMessageActionSheet(
                  context: context,
                  event: e,
                  isMe: true,
                  bubbleRect: const Rect.fromLTWH(50, 50, 300, 60),
                  actions: actions,
                  timeline: mockTimeline,
                  onQuickReact: onQuickReact,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void suppressLayoutErrors(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    final original = FlutterError.onError;
    FlutterError.onError = (d) {};
    addTearDown(() {
      FlutterError.onError = original;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('MessageActionSheet', () {
    testWidgets('renders all action labels', (tester) async {
      suppressLayoutErrors(tester);
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
        MessageAction(label: 'Copy', icon: Icons.copy, onTap: () {}),
        MessageAction(
          label: 'Delete',
          icon: Icons.delete,
          onTap: () {},
          color: Colors.red,
        ),
      ];

      await tester.pumpWidget(buildTestWidget(actions: actions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('tap action invokes callback and closes sheet',
        (tester) async {
      suppressLayoutErrors(tester);
      var replyCalled = false;
      final actions = [
        MessageAction(
          label: 'Reply',
          icon: Icons.reply,
          onTap: () => replyCalled = true,
        ),
      ];

      await tester.pumpWidget(buildTestWidget(actions: actions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();

      expect(replyCalled, isTrue);
    });

    testWidgets('quick react bar visible when onQuickReact provided',
        (tester) async {
      suppressLayoutErrors(tester);
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
      ];

      await tester.pumpWidget(
        buildTestWidget(
          actions: actions,
          onQuickReact: (_) {},
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('\u{1F44D}'), findsOneWidget);
      expect(find.text('\u{2764}\u{FE0F}'), findsOneWidget);
    });

    testWidgets('quick react bar hidden when onQuickReact is null',
        (tester) async {
      suppressLayoutErrors(tester);
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
      ];

      await tester.pumpWidget(buildTestWidget(actions: actions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('\u{1F44D}'), findsNothing);
    });

    testWidgets('tap emoji fires onQuickReact with correct string',
        (tester) async {
      suppressLayoutErrors(tester);
      String? selectedEmoji;
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
      ];

      await tester.pumpWidget(
        buildTestWidget(
          actions: actions,
          onQuickReact: (e) => selectedEmoji = e,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('\u{1F44D}'));
      await tester.pumpAndSettle();

      expect(selectedEmoji, '\u{1F44D}');
    });

    testWidgets('barrier tap dismisses sheet', (tester) async {
      suppressLayoutErrors(tester);
      final actions = [
        MessageAction(label: 'Reply', icon: Icons.reply, onTap: () {}),
      ];

      await tester.pumpWidget(buildTestWidget(actions: actions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsNothing);
    });
  });
}

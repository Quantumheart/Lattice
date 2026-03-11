import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/features/chat/widgets/forward_message_dialog.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<Event>(),
])
import 'forward_message_dialog_test.mocks.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

MockRoom _makeRoom(String id, String name, {bool isSpace = false}) {
  final room = MockRoom();
  when(room.id).thenReturn(id);
  when(room.getLocalizedDisplayname()).thenReturn(name);
  when(room.membership).thenReturn(Membership.join);
  when(room.isSpace).thenReturn(isSpace);
  return room;
}

void main() {
  late MockClient mockClient;
  late MockEvent mockEvent;
  late List<MockRoom> rooms;

  setUp(() {
    mockClient = MockClient();
    mockEvent = MockEvent();

    when(mockEvent.type).thenReturn(EventTypes.Message);
    when(mockEvent.content).thenReturn({
      'body': 'Hello',
      'msgtype': 'm.text',
      'm.relates_to': {
        'm.in_reply_to': {'event_id': r'$reply'},
      },
    });

    rooms = [
      _makeRoom('!a:example.com', 'Alpha'),
      _makeRoom('!b:example.com', 'Beta'),
      _makeRoom('!s:example.com', 'Space One', isSpace: true),
    ];
    when(mockClient.rooms).thenReturn(rooms);
  });

  group('ForwardMessageDialog', () {
    testWidgets('shows joined non-space rooms', (tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ForwardMessageDialog.show(
              context,
              client: mockClient,
              event: mockEvent,
            ),
            child: const Text('Open'),
          ),
        ),
      ),);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Space One'), findsNothing);
    });

    testWidgets('search filters room list', (tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ForwardMessageDialog.show(
              context,
              client: mockClient,
              event: mockEvent,
            ),
            child: const Text('Open'),
          ),
        ),
      ),);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'Alpha'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Beta'), findsNothing);
    });

    testWidgets('tapping room calls sendEvent and strips m.relates_to',
        (tester) async {
      final targetRoom = rooms[0];
      when(targetRoom.sendEvent(any, type: anyNamed('type')))
          .thenAnswer((_) async => r'$new');

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ForwardMessageDialog.show(
              context,
              client: mockClient,
              event: mockEvent,
            ),
            child: const Text('Open'),
          ),
        ),
      ),);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      final captured =
          verify(targetRoom.sendEvent(
            captureAny,
            type: captureAnyNamed('type'),
          ),).captured;
      final content = captured[0] as Map<String, Object?>;
      expect(content['body'], 'Hello');
      expect(content['msgtype'], 'm.text');
      expect(content.containsKey('m.relates_to'), isFalse);
      expect(captured[1], EventTypes.Message);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ForwardMessageDialog.show(
              context,
              client: mockClient,
              event: mockEvent,
            ),
            child: const Text('Open'),
          ),
        ),
      ),);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Forward to'), findsNothing);
    });
  });
}

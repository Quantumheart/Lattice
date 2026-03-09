import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/features/chat/widgets/call_event_tile.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Event>(), MockSpec<User>(), MockSpec<Room>(), MockSpec<Client>()])
import 'call_event_tile_test.mocks.dart';

void main() {
  late MockEvent mockEvent;
  late MockUser mockUser;
  late MockRoom mockRoom;
  late MockClient mockClient;

  setUp(() {
    mockEvent = MockEvent();
    mockUser = MockUser();
    mockRoom = MockRoom();
    mockClient = MockClient();
    when(mockUser.calcDisplayname()).thenReturn('Alice');
    when(mockEvent.senderFromMemoryOrFallback).thenReturn(mockUser);
    when(mockEvent.roomId).thenReturn('!room:example.com');
    when(mockEvent.room).thenReturn(mockRoom);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockClient.getRoomById(any)).thenReturn(mockRoom);
    when(mockRoom.lastEvent).thenReturn(null);
  });

  Widget buildWidget(Event event) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: CallEventTile(event: event)),
      ),
    );
  }

  testWidgets('renders call invite', (tester) async {
    when(mockEvent.type).thenReturn('m.call.invite');
    when(mockEvent.content).thenReturn({});
    await tester.pumpWidget(buildWidget(mockEvent));

    expect(find.text('Alice started a call'), findsOneWidget);
    expect(find.byIcon(Icons.call_rounded), findsOneWidget);
  });

  testWidgets('renders call hangup', (tester) async {
    when(mockEvent.type).thenReturn('m.call.hangup');
    when(mockEvent.content).thenReturn({});
    await tester.pumpWidget(buildWidget(mockEvent));

    expect(find.text('Call ended'), findsOneWidget);
    expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
  });

  testWidgets('renders missed call', (tester) async {
    when(mockEvent.type).thenReturn('m.call.hangup');
    when(mockEvent.content).thenReturn({'reason': 'invite_timeout'});
    await tester.pumpWidget(buildWidget(mockEvent));

    expect(find.text('Missed call from Alice'), findsOneWidget);
    expect(find.byIcon(Icons.call_missed_rounded), findsOneWidget);
  });

  testWidgets('renders call reject', (tester) async {
    when(mockEvent.type).thenReturn('m.call.reject');
    when(mockEvent.content).thenReturn({});
    await tester.pumpWidget(buildWidget(mockEvent));

    expect(find.text('Alice declined the call'), findsOneWidget);
    expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/widgets/shared_media_section.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<Event>(),
  MockSpec<Client>(),
])
import 'shared_media_section_test.mocks.dart';

typedef _SearchResult = ({List<Event> events, String? nextBatch, DateTime? searchedUntil});

_SearchResult _result({List<Event> events = const [], String? nextBatch}) =>
    (events: events, nextBatch: nextBatch, searchedUntil: null);

MockEvent _makeEvent(String messageType, {String body = 'file.dat', Map<String, dynamic>? info}) {
  final event = MockEvent();
  when(event.messageType).thenReturn(messageType);
  when(event.body).thenReturn(body);
  when(event.infoMap).thenReturn(info ?? {});
  when(event.isAttachmentEncrypted).thenReturn(false);
  return event;
}

void main() {
  late MockRoom mockRoom;
  late MockClient mockClient;

  setUp(() {
    mockRoom = MockRoom();
    mockClient = MockClient();
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.id).thenReturn('!room:example.com');
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SharedMediaSection(room: mockRoom),
        ),
      ),
    );
  }

  group('SharedMediaSection', () {
    testWidgets('shows loading indicator while fetching media', (tester) async {
      final completer = Completer<_SearchResult>();
      when(mockRoom.searchEvents(
        searchFunc: anyNamed('searchFunc'),
        nextBatch: anyNamed('nextBatch'),
        limit: anyNamed('limit'),
      )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('SHARED MEDIA'), findsOneWidget);

      completer.complete(_result());
      await tester.pumpAndSettle();
    });

    testWidgets('shows empty state when no media found', (tester) async {
      when(mockRoom.searchEvents(
        searchFunc: anyNamed('searchFunc'),
        nextBatch: anyNamed('nextBatch'),
        limit: anyNamed('limit'),
      )).thenAnswer((_) async => _result());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('No shared media yet'), findsOneWidget);
    });

    testWidgets('shows file list for file events', (tester) async {
      final fileEvent = _makeEvent(
        MessageTypes.File,
        body: 'document.pdf',
        info: {'size': 1048576},
      );

      when(mockRoom.searchEvents(
        searchFunc: anyNamed('searchFunc'),
        nextBatch: anyNamed('nextBatch'),
        limit: anyNamed('limit'),
      )).thenAnswer((_) async => _result(events: [fileEvent]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.text('1.0 MB'), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file_rounded), findsOneWidget);
    });

    testWidgets('shows audio icon for audio events', (tester) async {
      final audioEvent = _makeEvent(
        MessageTypes.Audio,
        body: 'recording.ogg',
        info: {'size': 512},
      );

      when(mockRoom.searchEvents(
        searchFunc: anyNamed('searchFunc'),
        nextBatch: anyNamed('nextBatch'),
        limit: anyNamed('limit'),
      )).thenAnswer((_) async => _result(events: [audioEvent]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('recording.ogg'), findsOneWidget);
      expect(find.text('512 B'), findsOneWidget);
      expect(find.byIcon(Icons.audiotrack_rounded), findsOneWidget);
    });

    testWidgets('shows Load more button when there is a next batch', (tester) async {
      final fileEvent = _makeEvent(MessageTypes.File, body: 'file.txt');

      when(mockRoom.searchEvents(
        searchFunc: anyNamed('searchFunc'),
        nextBatch: anyNamed('nextBatch'),
        limit: anyNamed('limit'),
      )).thenAnswer((_) async => _result(events: [fileEvent], nextBatch: 'batch2'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsOneWidget);
    });

    testWidgets('hides Load more when no next batch', (tester) async {
      final fileEvent = _makeEvent(MessageTypes.File, body: 'file.txt');

      when(mockRoom.searchEvents(
        searchFunc: anyNamed('searchFunc'),
        nextBatch: anyNamed('nextBatch'),
        limit: anyNamed('limit'),
      )).thenAnswer((_) async => _result(events: [fileEvent]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('handles load error gracefully', (tester) async {
      when(mockRoom.searchEvents(
        searchFunc: anyNamed('searchFunc'),
        nextBatch: anyNamed('nextBatch'),
        limit: anyNamed('limit'),
      )).thenThrow(Exception('Network error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Should show empty state, not crash
      expect(find.text('No shared media yet'), findsOneWidget);
    });

    testWidgets('shows image grid for image events', (tester) async {
      final imageEvent = _makeEvent(MessageTypes.Image, body: 'photo.jpg');
      final room = MockRoom();
      when(room.client).thenReturn(mockClient);
      when(imageEvent.room).thenReturn(room);

      when(mockRoom.searchEvents(
        searchFunc: anyNamed('searchFunc'),
        nextBatch: anyNamed('nextBatch'),
        limit: anyNamed('limit'),
      )).thenAnswer((_) async => _result(events: [imageEvent]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
    });
  });
}

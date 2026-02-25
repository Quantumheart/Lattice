import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/services/chat_search_controller.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<Event>(),
])
import 'chat_search_controller_test.mocks.dart';

void main() {
  late MockRoom mockRoom;
  late ChatSearchController controller;

  setUp(() {
    mockRoom = MockRoom();
    controller = ChatSearchController(
      roomId: '!room:example.com',
      getRoom: () => mockRoom,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('open / close', () {
    test('open sets isSearching to true', () {
      controller.open();
      expect(controller.isSearching, isTrue);
    });

    test('close resets all state', () {
      controller.open();
      controller.close();
      expect(controller.isSearching, isFalse);
      expect(controller.results, isEmpty);
      expect(controller.nextBatch, isNull);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.query, isEmpty);
    });

    test('close cancels highlight timer', () {
      controller.setHighlight('evt1');
      expect(controller.highlightedEventId, 'evt1');
      controller.close();
      // close() resets _highlightedEventId indirectly by cancelling the timer
      // and resetting state — verify it doesn't fire after close.
      expect(controller.highlightedEventId, isNull);
    });
  });

  group('onQueryChanged', () {
    test('short query clears results without searching', () {
      controller.open();
      controller.onQueryChanged('ab');
      expect(controller.query, 'ab');
      expect(controller.results, isEmpty);
      verifyNever(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
        nextBatch: anyNamed('nextBatch'),
      ));
    });

    test('trims whitespace from query', () {
      controller.open();
      controller.onQueryChanged('  ab  ');
      expect(controller.query, 'ab');
    });
  });

  group('performSearch', () {
    test('sets results on success', () async {
      controller.open();
      controller.onQueryChanged('hello');

      final mockEvent = MockEvent();
      when(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => (
            events: <Event>[mockEvent],
            nextBatch: 'batch2' as String?,
            searchedUntil: null as DateTime?,
          ));

      await controller.performSearch();

      expect(controller.results, hasLength(1));
      expect(controller.nextBatch, 'batch2');
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
    });

    test('sets error on failure', () async {
      controller.open();
      controller.onQueryChanged('hello');

      when(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
        nextBatch: anyNamed('nextBatch'),
      )).thenThrow(Exception('Network error'));

      await controller.performSearch();

      expect(controller.results, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNotNull);
    });

    test('loadMore appends to existing results', () async {
      controller.open();
      controller.onQueryChanged('hello');

      final event1 = MockEvent();
      final event2 = MockEvent();

      when(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
        nextBatch: argThat(isNull, named: 'nextBatch'),
      )).thenAnswer((_) async => (
            events: <Event>[event1],
            nextBatch: 'batch2' as String?,
            searchedUntil: null as DateTime?,
          ));

      await controller.performSearch();
      expect(controller.results, hasLength(1));

      when(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
        nextBatch: argThat(equals('batch2'), named: 'nextBatch'),
      )).thenAnswer((_) async => (
            events: <Event>[event2],
            nextBatch: null as String?,
            searchedUntil: null as DateTime?,
          ));

      await controller.performSearch(loadMore: true);
      expect(controller.results, hasLength(2));
      expect(controller.nextBatch, isNull);
    });

    test('skips search when query is too short', () async {
      controller.open();
      controller.onQueryChanged('ab');
      await controller.performSearch();
      verifyNever(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
        nextBatch: anyNamed('nextBatch'),
      ));
    });

    test('skips search when room is null', () async {
      final ctrl = ChatSearchController(
        roomId: '!room:example.com',
        getRoom: () => null,
      );
      ctrl.open();
      ctrl.onQueryChanged('hello');
      await ctrl.performSearch();
      expect(ctrl.results, isEmpty);
      ctrl.dispose();
    });
  });

  group('setHighlight', () {
    test('sets highlighted event id', () {
      controller.setHighlight('evt1');
      expect(controller.highlightedEventId, 'evt1');
    });

    test('replaces previous highlight', () {
      controller.setHighlight('evt1');
      controller.setHighlight('evt2');
      expect(controller.highlightedEventId, 'evt2');
    });
  });

  group('notifyListeners', () {
    test('notifies on open', () {
      var count = 0;
      controller.addListener(() => count++);
      controller.open();
      expect(count, 1);
    });

    test('notifies on close', () {
      controller.open();
      var count = 0;
      controller.addListener(() => count++);
      controller.close();
      expect(count, 1);
    });

    test('notifies on setHighlight', () {
      var count = 0;
      controller.addListener(() => count++);
      controller.setHighlight('evt1');
      expect(count, 1);
    });
  });
}

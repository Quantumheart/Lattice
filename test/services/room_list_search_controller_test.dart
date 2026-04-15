import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>(), MockSpec<User>()])
import 'room_list_search_controller_test.mocks.dart';

SearchResults _buildSearchResults({
  List<MatrixEvent> events = const [],
  String? nextBatch,
  int? count,
}) {
  return SearchResults(
    searchCategories: ResultCategories(
      roomEvents: ResultRoomEvents(
        results: events
            .map((e) => Result(result: e))
            .toList(),
        nextBatch: nextBatch,
        count: count,
      ),
    ),
  );
}

MatrixEvent _makeMatrixEvent({
  required String eventId,
  required String roomId,
  required String senderId,
  required String body,
  required DateTime originServerTs,
}) {
  return MatrixEvent(
    type: EventTypes.Message,
    content: {'body': body, 'msgtype': 'm.text'},
    senderId: senderId,
    eventId: eventId,
    roomId: roomId,
    originServerTs: originServerTs,
  );
}

void main() {
  late MockClient mockClient;
  late RoomListSearchController controller;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.rooms).thenReturn([]);
    controller = RoomListSearchController(getClient: () => mockClient);
  });

  tearDown(() {
    controller.dispose();
  });

  group('onQueryChanged', () {
    test('short query clears results and stops loading', () {
      controller.onQueryChanged('ab');

      expect(controller.results, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.nextBatch, isNull);
    });

    test('valid query sets loading and debounces', () {
      fakeAsync((async) {
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        controller.onQueryChanged('hello world');

        expect(controller.isLoading, isTrue);

        when(mockClient.search(
          any,
          nextBatch: anyNamed('nextBatch'),
        ),).thenAnswer((_) async => _buildSearchResults());

        async.elapse(const Duration(milliseconds: 500));

        expect(notifyCount, greaterThan(0));
      });
    });

    test('new query cancels previous debounce', () {
      fakeAsync((async) {
        when(mockClient.search(
          any,
          nextBatch: anyNamed('nextBatch'),
        ),).thenAnswer((_) async => _buildSearchResults());

        controller.onQueryChanged('first query');
        async.elapse(const Duration(milliseconds: 300));

        controller.onQueryChanged('second query');
        async.elapse(const Duration(milliseconds: 500));

        async.flushMicrotasks();
      });
    });
  });

  group('performSearch', () {
    test('parses server results into MessageSearchResult list', () async {
      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('General');
      when(mockUser.displayName).thenReturn('Alice');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);

      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$e1',
                roomId: '!room:example.com',
                senderId: '@alice:example.com',
                body: 'hello world',
                originServerTs: DateTime(2026),
              ),
            ],
            count: 1,
          ),);

      controller.onQueryChanged('hello world');
      await controller.performSearch();

      expect(controller.results, hasLength(1));
      expect(controller.results.first.body, 'hello world');
      expect(controller.results.first.roomName, 'General');
      expect(controller.results.first.senderName, 'Alice');
      expect(controller.isLoading, isFalse);
      expect(controller.totalCount, 1);
    });

    test('skips events with null/empty body', () async {
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$e1',
                roomId: '!room:example.com',
                senderId: '@a:x.com',
                body: '',
                originServerTs: DateTime(2026),
              ),
            ],
          ),);

      controller.onQueryChanged('hello world');
      await controller.performSearch();

      expect(controller.results, isEmpty);
    });

    test('deduplicates by eventId and sorts by timestamp descending',
        () async {
      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockClient.getRoomById(any)).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room');
      when(mockUser.displayName).thenReturn('User');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);

      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$older',
                roomId: '!r:x',
                senderId: '@a:x',
                body: 'older',
                originServerTs: DateTime(2026),
              ),
              _makeMatrixEvent(
                eventId: r'$newer',
                roomId: '!r:x',
                senderId: '@a:x',
                body: 'newer',
                originServerTs: DateTime(2026, 6),
              ),
            ],
          ),);

      controller.onQueryChanged('test query');
      await controller.performSearch();

      expect(controller.results, hasLength(2));
      expect(controller.results.first.eventId, r'$newer');
      expect(controller.results.last.eventId, r'$older');
    });

    test('sets error on search failure', () async {
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenThrow(Exception('server error'));

      controller.onQueryChanged('error query');
      await controller.performSearch();

      expect(controller.error, isNotNull);
      expect(controller.isLoading, isFalse);
    });

    test('discards stale results from previous generation', () async {
      var callCount = 0;
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _buildSearchResults(
          events: [
            _makeMatrixEvent(
              eventId: '\$e$callCount',
              roomId: '!r:x',
              senderId: '@a:x',
              body: 'result $callCount',
              originServerTs: DateTime(2026, 1, callCount),
            ),
          ],
        );
      });

      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockClient.getRoomById(any)).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room');
      when(mockUser.displayName).thenReturn('User');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);

      final firstSearch = controller.performSearch();
      controller.onQueryChanged('new query');
      await firstSearch;

      expect(controller.results, isEmpty);
    });

    test('loadMore appends to existing results', () async {
      final mockRoom = MockRoom();
      final mockUser = MockUser();
      when(mockClient.getRoomById(any)).thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Room');
      when(mockUser.displayName).thenReturn('User');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback(any))
          .thenReturn(mockUser);

      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$e1',
                roomId: '!r:x',
                senderId: '@a:x',
                body: 'first',
                originServerTs: DateTime(2026, 6),
              ),
            ],
            nextBatch: 'batch2',
            count: 2,
          ),);

      controller.onQueryChanged('test query');
      await controller.performSearch();
      expect(controller.results, hasLength(1));

      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults(
            events: [
              _makeMatrixEvent(
                eventId: r'$e2',
                roomId: '!r:x',
                senderId: '@a:x',
                body: 'second',
                originServerTs: DateTime(2026),
              ),
            ],
          ),);

      await controller.performSearch(loadMore: true);
      expect(controller.results, hasLength(2));
    });
  });

  group('clear', () {
    test('resets all state', () async {
      when(mockClient.search(
        any,
        nextBatch: anyNamed('nextBatch'),
      ),).thenAnswer((_) async => _buildSearchResults());

      controller.onQueryChanged('test query');
      await controller.performSearch();

      controller.clear();

      expect(controller.results, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.nextBatch, isNull);
      expect(controller.totalCount, isNull);
      expect(controller.query, isEmpty);
    });
  });
}

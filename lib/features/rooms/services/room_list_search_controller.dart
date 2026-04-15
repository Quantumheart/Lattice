import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:matrix/matrix.dart';

// ── Data class ──────────────────────────────────────────────
class MessageSearchResult {
  const MessageSearchResult({
    required this.roomId,
    required this.roomName,
    required this.senderName,
    required this.senderId,
    required this.body,
    required this.eventId,
    required this.originServerTs,
  });

  final String roomId;
  final String roomName;
  final String senderName;
  final String senderId;
  final String body;
  final String eventId;
  final DateTime originServerTs;
}

// ── Controller ──────────────────────────────────────────────
class RoomListSearchController extends ChangeNotifier {
  RoomListSearchController({required this.getClient});

  final Client Function() getClient;

  // ── Constants ──────────────────────────────────────────────
  static const _searchBatchLimit = 20;
  static const minQueryLength = 3;
  static const _debounceDuration = Duration(milliseconds: 500);

  // ── State ─────────────────────────────────────────────────
  List<MessageSearchResult> _results = [];
  List<MessageSearchResult> get results => List.unmodifiable(_results);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  String? _nextBatch;
  String? get nextBatch => _nextBatch;

  int? _totalCount;
  int? get totalCount => _totalCount;

  String _query = '';
  String get query => _query;

  bool _localSearchDone = false;

  bool _disposed = false;
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  Set<String>? _scopeRoomIds;

  // ── Actions ───────────────────────────────────────────────

  void onQueryChanged(String text, {Set<String>? scopeRoomIds}) {
    _debounceTimer?.cancel();
    _query = text.trim();
    _scopeRoomIds = scopeRoomIds;

    if (_query.length < minQueryLength) {
      _results = [];
      _nextBatch = null;
      _totalCount = null;
      _error = null;
      _isLoading = false;
      _searchGeneration++;
      if (!_disposed) notifyListeners();
      return;
    }

    _isLoading = true;
    if (!_disposed) notifyListeners();
    _debounceTimer = Timer(_debounceDuration, performSearch);
  }

  Future<void> performSearch({bool loadMore = false}) async {
    if (_disposed) return;
    if (_query.length < minQueryLength) return;

    final client = getClient();
    final searchQuery = _query;
    final generation = ++_searchGeneration;

    _isLoading = true;
    _error = null;
    if (!loadMore) {
      _results = [];
      _nextBatch = null;
      _totalCount = null;
      _localSearchDone = false;
    }
    notifyListeners();

    try {
      debugPrint('[Kohera] Searching messages for: $searchQuery');

      // Run server search and local encrypted search in parallel.
      // On loadMore, only paginate the server search — local search
      // scans the full local DB in one pass on the initial call.
      final scopeIds = _scopeRoomIds;

      final serverFuture = client.search(
        Categories(
          roomEvents: RoomEventsCriteria(
            searchTerm: searchQuery,
            orderBy: SearchOrder.recent,
            keys: [KeyKind.contentBody],
            filter: SearchFilter(
              types: ['m.room.message'],
              limit: _searchBatchLimit,
              rooms: scopeIds?.toList(),
            ),
            eventContext: IncludeEventContext(afterLimit: 0, beforeLimit: 0),
          ),
        ),
        nextBatch: loadMore ? _nextBatch : null,
      );

      final localFuture = (!loadMore || !_localSearchDone)
          ? _searchEncryptedRooms(client, searchQuery, scopeRoomIds: scopeIds)
          : Future<List<MessageSearchResult>>.value([]);

      final results = await Future.wait([serverFuture, localFuture]);

      if (_disposed || generation != _searchGeneration) return;

      final response = results[0] as SearchResults;
      final localResults = results[1] as List<MessageSearchResult>;
      _localSearchDone = true;

      // Parse server results
      final serverResults = <MessageSearchResult>[];
      final roomEvents = response.searchCategories.roomEvents;

      if (roomEvents != null) {
        for (final result in roomEvents.results ?? <Result>[]) {
          final event = result.result;
          if (event == null) continue;
          final roomId = event.roomId;
          if (roomId == null) continue;

          final rawBody = event.content.tryGet<String>('body');
          if (rawBody == null || rawBody.isEmpty) continue;

          final room = client.getRoomById(roomId);
          final roomName =
              room?.getLocalizedDisplayname() ?? roomId;
          final senderName = room
                  ?.unsafeGetUserFromMemoryOrFallback(event.senderId)
                  .displayName ??
              event.senderId;

          serverResults.add(MessageSearchResult(
            roomId: roomId,
            roomName: roomName,
            senderName: senderName,
            senderId: event.senderId,
            body: stripReplyFallback(rawBody),
            eventId: event.eventId,
            originServerTs: event.originServerTs,
          ),);
        }

        _nextBatch = roomEvents.nextBatch;
        _totalCount = roomEvents.count;
      }

      // Merge, deduplicate by eventId, and sort by timestamp descending
      final merged = <String, MessageSearchResult>{};
      final previousResults = loadMore ? _results : <MessageSearchResult>[];
      for (final r in previousResults) {
        merged[r.eventId] = r;
      }
      for (final r in serverResults) {
        merged[r.eventId] = r;
      }
      for (final r in localResults) {
        merged.putIfAbsent(r.eventId, () => r);
      }

      final sorted = merged.values.toList()
        ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));

      _results = sorted;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Kohera] Message search error: $e');
      if (_disposed || generation != _searchGeneration) return;
      _isLoading = false;
      _error = 'Message search failed. The server may not support it.';
      notifyListeners();
    }
  }

  Future<List<MessageSearchResult>> _searchEncryptedRooms(
    Client client,
    String query, {
    Set<String>? scopeRoomIds,
  }) async {
    var encryptedRooms =
        client.rooms.where((room) => room.encrypted).toList();
    if (scopeRoomIds != null) {
      encryptedRooms =
          encryptedRooms.where((room) => scopeRoomIds.contains(room.id)).toList();
    }
    if (encryptedRooms.isEmpty) return [];

    debugPrint(
      '[Kohera] Searching ${encryptedRooms.length} encrypted rooms locally',
    );

    // Search rooms in batches to avoid excessive concurrent DB queries.
    const batchSize = 5;
    final allResults = <MessageSearchResult>[];
    for (var i = 0; i < encryptedRooms.length; i += batchSize) {
      if (_disposed) return allResults;
      final batch = encryptedRooms.sublist(
        i,
        i + batchSize > encryptedRooms.length
            ? encryptedRooms.length
            : i + batchSize,
      );
      final batchResults = await Future.wait(batch.map((room) async {
        try {
          final result = await room.searchEvents(
            searchTerm: query,
            limit: _searchBatchLimit,
          );
          return result.events
              .where((event) =>
                  event.type == EventTypes.Message &&
                  (event.content.tryGet<String>('body')?.isNotEmpty ?? false),)
              .map((event) {
                final rawBody = event.content.tryGet<String>('body') ?? '';
                return MessageSearchResult(
                    roomId: room.id,
                    roomName: room.getLocalizedDisplayname(),
                    senderName: room
                        .unsafeGetUserFromMemoryOrFallback(event.senderId)
                        .displayName ?? event.senderId,
                    senderId: event.senderId,
                    body: stripReplyFallback(rawBody),
                    eventId: event.eventId,
                    originServerTs: event.originServerTs,
                  );
              })
              .toList();
        } catch (e) {
          debugPrint(
            '[Kohera] Local search failed for ${room.id}: $e',
          );
          return <MessageSearchResult>[];
        }
      }),);
      allResults.addAll(batchResults.expand((list) => list));
    }
    return allResults;
  }

  void clear() {
    _debounceTimer?.cancel();
    _searchGeneration++;
    _results = [];
    _nextBatch = null;
    _totalCount = null;
    _localSearchDone = false;
    _isLoading = false;
    _error = null;
    _query = '';
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}

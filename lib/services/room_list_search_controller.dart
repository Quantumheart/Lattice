import 'dart:async';
import 'package:flutter/foundation.dart';
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
  List<MessageSearchResult> get results => _results;

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

  bool _disposed = false;
  Timer? _debounceTimer;

  // ── Actions ───────────────────────────────────────────────

  void onQueryChanged(String text) {
    _debounceTimer?.cancel();
    _query = text.trim();

    if (_query.length < minQueryLength) {
      _results = [];
      _nextBatch = null;
      _totalCount = null;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();
    _debounceTimer = Timer(_debounceDuration, () {
      performSearch();
    });
  }

  Future<void> performSearch({bool loadMore = false}) async {
    if (_query.length < minQueryLength) return;

    final client = getClient();
    final searchQuery = _query;

    _isLoading = true;
    _error = null;
    if (!loadMore) {
      _results = [];
      _nextBatch = null;
      _totalCount = null;
    }
    notifyListeners();

    try {
      debugPrint('[Lattice] Searching messages for: $searchQuery');
      final response = await client.search(
        Categories(
          roomEvents: RoomEventsCriteria(
            searchTerm: searchQuery,
            orderBy: SearchOrder.recent,
            keys: [KeyKind.contentBody],
            filter: SearchFilter(
              types: ['m.room.message'],
              limit: _searchBatchLimit,
            ),
            eventContext: IncludeEventContext(afterLimit: 0, beforeLimit: 0),
          ),
        ),
        nextBatch: loadMore ? _nextBatch : null,
      );

      if (_disposed) return;

      // Stale query guard
      if (_query != searchQuery) return;

      final roomEvents = response.searchCategories.roomEvents;
      final newResults = <MessageSearchResult>[];

      if (roomEvents != null) {
        for (final result in roomEvents.results ?? <Result>[]) {
          final event = result.result;
          if (event == null) continue;
          final roomId = event.roomId;
          if (roomId == null) continue;

          final body = event.content.tryGet<String>('body');
          if (body == null || body.isEmpty) continue;

          final room = client.getRoomById(roomId);
          final roomName =
              room?.getLocalizedDisplayname() ?? roomId;
          final senderName = room
                  ?.unsafeGetUserFromMemoryOrFallback(event.senderId)
                  .displayName ??
              event.senderId;

          newResults.add(MessageSearchResult(
            roomId: roomId,
            roomName: roomName,
            senderName: senderName,
            senderId: event.senderId,
            body: body,
            eventId: event.eventId,
            originServerTs: event.originServerTs,
          ));
        }

        _nextBatch = roomEvents.nextBatch;
        _totalCount = roomEvents.count;
      }

      if (loadMore) {
        _results.addAll(newResults);
      } else {
        _results = newResults;
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Lattice] Message search error: $e');
      if (_disposed) return;
      if (_query != searchQuery) return;
      _isLoading = false;
      _error = 'Message search failed. The server may not support it.';
      notifyListeners();
    }
  }

  void clear() {
    _debounceTimer?.cancel();
    _results = [];
    _nextBatch = null;
    _totalCount = null;
    _isLoading = false;
    _error = null;
    _query = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}

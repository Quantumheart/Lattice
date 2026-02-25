import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class ChatSearchController extends ChangeNotifier {
  ChatSearchController({required this.roomId, required this.getRoom});

  final String roomId;
  final Room? Function() getRoom;

  // ── Constants ──────────────────────────────────────────────
  static const searchBatchLimit = 50;
  static const minQueryLength = 3;
  static const _debounceDuration = Duration(milliseconds: 500);

  // ── State ─────────────────────────────────────────────────
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  List<Event> _results = [];
  List<Event> get results => _results;

  String? _nextBatch;
  String? get nextBatch => _nextBatch;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  String? _highlightedEventId;
  String? get highlightedEventId => _highlightedEventId;

  String _query = '';
  String get query => _query;

  bool _disposed = false;

  Timer? _debounceTimer;
  Timer? _highlightTimer;

  // ── Actions ───────────────────────────────────────────────

  void open() {
    _isSearching = true;
    _results = [];
    _nextBatch = null;
    _error = null;
    _query = '';
    notifyListeners();
  }

  void close() {
    _debounceTimer?.cancel();
    _highlightTimer?.cancel();
    _highlightedEventId = null;
    _isSearching = false;
    _results = [];
    _nextBatch = null;
    _isLoading = false;
    _error = null;
    _query = '';
    notifyListeners();
  }

  void onQueryChanged(String text) {
    _debounceTimer?.cancel();
    _query = text.trim();

    if (_query.length < minQueryLength) {
      _results = [];
      _nextBatch = null;
      _error = null;
      notifyListeners();
      return;
    }

    notifyListeners();
    _debounceTimer = Timer(_debounceDuration, () {
      performSearch();
    });
  }

  Future<void> performSearch({bool loadMore = false}) async {
    if (_query.length < minQueryLength) return;

    final room = getRoom();
    if (room == null) return;

    _isLoading = true;
    _error = null;
    if (!loadMore) {
      _results = [];
      _nextBatch = null;
    }
    notifyListeners();

    try {
      debugPrint('[Lattice] Searching room for: $_query');
      final result = await room.searchEvents(
        searchTerm: _query,
        limit: searchBatchLimit,
        nextBatch: loadMore ? _nextBatch : null,
      );

      if (_disposed) return;

      if (loadMore) {
        _results.addAll(result.events);
      } else {
        _results = result.events.toList();
      }
      _nextBatch = result.nextBatch;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Lattice] Search error: $e');
      if (_disposed) return;
      _isLoading = false;
      _error = 'Search failed. Please try again.';
      notifyListeners();
    }
  }

  void setHighlight(String eventId) {
    _highlightTimer?.cancel();
    _highlightedEventId = eventId;
    notifyListeners();

    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
      _highlightedEventId = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _highlightTimer?.cancel();
    super.dispose();
  }
}

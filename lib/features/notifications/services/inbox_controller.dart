import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart' show Client;

// ── Filter enum ──────────────────────────────────────────────
enum InboxFilter { all, mentions }

// ── Grouped notification model ───────────────────────────────
class NotificationGroup {
  final String roomId;
  final String roomName;
  final List<matrix_sdk.Notification> notifications;

  const NotificationGroup({
    required this.roomId,
    required this.roomName,
    required this.notifications,
  });
}

// ── InboxController ──────────────────────────────────────────
class InboxController extends ChangeNotifier {
  InboxController({required Client client}) : _client = client;

  Client _client;
  Client get client => _client;
  bool _disposed = false;

  List<NotificationGroup> _grouped = [];
  List<NotificationGroup> get grouped => List.unmodifiable(_grouped);
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  String? _error;
  String? get error => _error;
  String? _nextToken;
  InboxFilter _filter = InboxFilter.all;
  InboxFilter get filter => _filter;

  Timer? _pollTimer;
  int _pollingRefCount = 0;

  int _fetchGeneration = 0;
  int _cachedUnreadCount = 0;

  // ── Public getters ─────────────────────────────────────────

  int get unreadCount => _cachedUnreadCount;

  bool get hasMore => _nextToken != null;

  // ── Unread count cache helper ──────────────────────────────

  void _updateUnreadCount() {
    var count = 0;
    for (final group in _grouped) {
      count += group.notifications.where((n) => !n.read).length;
    }
    _cachedUnreadCount = count;
  }

  // ── Fetch ──────────────────────────────────────────────────

  Future<void> fetch() async {
    final gen = ++_fetchGeneration;
    _isLoading = true;
    _error = null;
    if (!_disposed) notifyListeners();

    try {
      final response = await _client.getNotifications(
        limit: 30,
        only: _filter == InboxFilter.mentions ? 'highlight' : null,
      );
      if (_disposed || gen != _fetchGeneration) return;
      _nextToken = response.nextToken;
      _grouped = _groupByRoom(response.notifications);
      _updateUnreadCount();
    } catch (e) {
      if (_disposed || gen != _fetchGeneration) return;
      _error = e.toString();
      debugPrint('[Lattice] Inbox fetch error: $e');
    } finally {
      if (!_disposed && gen == _fetchGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_nextToken == null || _isLoading) return;

    final gen = ++_fetchGeneration;
    _isLoading = true;
    _error = null;
    if (!_disposed) notifyListeners();

    try {
      final response = await _client.getNotifications(
        limit: 30,
        from: _nextToken,
        only: _filter == InboxFilter.mentions ? 'highlight' : null,
      );
      if (_disposed || gen != _fetchGeneration) return;
      _nextToken = response.nextToken;

      // Merge new notifications into existing groups
      final all = <matrix_sdk.Notification>[];
      for (final group in _grouped) {
        all.addAll(group.notifications);
      }
      all.addAll(response.notifications);
      _grouped = _groupByRoom(all);
      _updateUnreadCount();
    } catch (e) {
      if (_disposed || gen != _fetchGeneration) return;
      _error = e.toString();
      debugPrint('[Lattice] Inbox loadMore error: $e');
    } finally {
      if (!_disposed && gen == _fetchGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // ── Filter ─────────────────────────────────────────────────

  void setFilter(InboxFilter newFilter) {
    if (_filter == newFilter) return;
    _filter = newFilter;
    _grouped = [];
    _nextToken = null;
    _updateUnreadCount();
    if (!_disposed) notifyListeners();
    unawaited(fetch().catchError((Object e) => debugPrint('[Lattice] Inbox fetch error: $e')));
  }

  // ── Polling ────────────────────────────────────────────────

  void startPolling() {
    _pollingRefCount++;
    if (_pollingRefCount == 1) {
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 7),
        (_) => _pollOnce(),
      );
    }
  }

  void stopPolling() {
    _pollingRefCount = (_pollingRefCount - 1).clamp(0, 999);
    if (_pollingRefCount == 0) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _pollOnce() async {
    if (_isLoading) return;
    try {
      final response = await _client.getNotifications(
        limit: 30,
        only: _filter == InboxFilter.mentions ? 'highlight' : null,
      );
      if (_disposed) return;

      // Merge polled notifications into existing groups so we don't
      // discard results the user loaded via loadMore().
      final all = <matrix_sdk.Notification>[];
      final existingIds = <String>{};
      for (final group in _grouped) {
        all.addAll(group.notifications);
        for (final n in group.notifications) {
          existingIds.add(n.event.eventId);
        }
      }
      for (final n in response.notifications) {
        if (!existingIds.contains(n.event.eventId)) {
          all.add(n);
        }
      }
      _grouped = _groupByRoom(all);
      _updateUnreadCount();
      _error = null;
      // Only update nextToken if we didn't already paginate further.
      _nextToken ??= response.nextToken;
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[Lattice] Inbox poll error: $e');
    }
  }

  // ── Mark as read ───────────────────────────────────────────

  Future<void> markRoomAsRead(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    // Prefer the latest notification event ID (always available on the
    // inbox screen) over room.lastEvent which may be null when the
    // room timeline hasn't been loaded.
    String? eventId;
    for (final group in _grouped) {
      if (group.roomId == roomId && group.notifications.isNotEmpty) {
        eventId = group.notifications.first.event.eventId;
        break;
      }
    }
    eventId ??= room.lastEvent?.eventId;
    if (eventId == null) return;

    try {
      await room.setReadMarker(eventId);
      // Re-fetch to update state
      await fetch();
    } catch (e) {
      debugPrint('[Lattice] Inbox markRoomAsRead error: $e');
    }
  }

  // ── Account switching ──────────────────────────────────────

  void updateClient(Client newClient) {
    if (identical(_client, newClient)) return;
    _client = newClient;
    _grouped = [];
    _nextToken = null;
    _isLoading = false;
    _error = null;
    _updateUnreadCount();
    stopPolling();
    if (!_disposed) notifyListeners();
    unawaited(fetch().catchError((Object e) => debugPrint('[Lattice] Inbox fetch error: $e')));
  }

  // ── Helpers ────────────────────────────────────────────────

  List<NotificationGroup> _groupByRoom(
      List<matrix_sdk.Notification> notifications,) {
    final map = <String, List<matrix_sdk.Notification>>{};
    final order = <String>[];

    for (final n in notifications) {
      map.putIfAbsent(n.roomId, () {
        order.add(n.roomId);
        return [];
      });
      map[n.roomId]!.add(n);
    }

    return order.map((roomId) {
      final room = _client.getRoomById(roomId);
      return NotificationGroup(
        roomId: roomId,
        roomName: room?.getLocalizedDisplayname() ?? roomId,
        notifications: map[roomId]!,
      );
    }).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}

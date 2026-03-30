import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart' show Client, MatrixException, Membership;

// ── Filter enum ──────────────────────────────────────────────
enum InboxFilter { all, mentions, invitations }

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
  bool _markingAsRead = false;
  bool _tokenExpired = false;

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
      if (_isTokenExpired(e)) {
        _tokenExpired = true;
        _isLoading = false;
        return;
      }
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

  int get invitationCount =>
      _client.rooms.where((r) => r.membership == Membership.invite).length;

  void setFilter(InboxFilter newFilter) {
    if (_filter == newFilter) return;
    _filter = newFilter;
    if (newFilter == InboxFilter.invitations) {
      if (!_disposed) notifyListeners();
      return;
    }
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
    if (_isLoading || _markingAsRead || _tokenExpired) return;
    try {
      final response = await _client.getNotifications(
        limit: 30,
        only: _filter == InboxFilter.mentions ? 'highlight' : null,
      );
      if (_disposed) return;

      final freshIds = <String>{};
      for (final n in response.notifications) {
        freshIds.add(n.event.eventId);
      }

      final all = <matrix_sdk.Notification>[...response.notifications];
      for (final group in _grouped) {
        for (final n in group.notifications) {
          if (!freshIds.contains(n.event.eventId)) {
            all.add(n);
          }
        }
      }
      _grouped = _groupByRoom(all);
      _updateUnreadCount();
      _error = null;
      _nextToken ??= response.nextToken;
      if (!_disposed) notifyListeners();
    } catch (e) {
      if (_isTokenExpired(e)) {
        _tokenExpired = true;
        return;
      }
      debugPrint('[Lattice] Inbox poll error: $e');
    }
  }

  // ── Mark as read ───────────────────────────────────────────

  Future<void> markRoomAsRead(String roomId) async {
    if (_tokenExpired) return;
    final room = _client.getRoomById(roomId);
    if (room == null) return;

    String? eventId;
    var latestTs = -1;
    for (final group in _grouped) {
      if (group.roomId == roomId) {
        for (final n in group.notifications) {
          if (n.ts > latestTs) {
            latestTs = n.ts;
            eventId = n.event.eventId;
          }
        }
        break;
      }
    }
    eventId ??= room.lastEvent?.eventId;
    if (eventId == null) return;

    _markingAsRead = true;
    _grouped = [
      for (final g in _grouped)
        if (g.roomId != roomId) g,
    ];
    _updateUnreadCount();
    if (!_disposed) notifyListeners();

    try {
      await room.setReadMarker(eventId, mRead: eventId);
      await fetch();
    } catch (e) {
      if (_isTokenExpired(e)) {
        _tokenExpired = true;
        _markingAsRead = false;
        return;
      }
      debugPrint('[Lattice] Inbox markRoomAsRead error: $e');
      await fetch();
    } finally {
      _markingAsRead = false;
    }
  }

  // ── Account switching ──────────────────────────────────────

  void updateClient(Client newClient) {
    _tokenExpired = false;
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

  // ── Token expiry guard ─────────────────────────────────────

  static bool _isTokenExpired(Object e) =>
      e is MatrixException && e.errcode == 'M_UNKNOWN_TOKEN';

  // ── Helpers ────────────────────────────────────────────────

  List<NotificationGroup> _groupByRoom(
      List<matrix_sdk.Notification> notifications,) {
    final map = <String, List<matrix_sdk.Notification>>{};
    final order = <String>[];

    for (final n in notifications) {
      if (n.read) continue;
      final room = _client.getRoomById(n.roomId);
      if (room == null || room.membership != Membership.join) continue;
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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/features/notifications/services/apns_push_service.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart'
    show Client, Event, EventTypes, MatrixException, Membership;

// ── Word-boundary helper ─────────────────────────────────────

bool _containsWord(String text, String word) {
  var start = 0;
  while (true) {
    final index = text.indexOf(word, start);
    if (index == -1) return false;
    final before = index > 0 ? text.codeUnitAt(index - 1) : 0;
    final afterIdx = index + word.length;
    final after = afterIdx < text.length ? text.codeUnitAt(afterIdx) : 0;
    final boundedLeft = !_isLetter(before);
    final boundedRight = !_isLetter(after);
    if (boundedLeft && boundedRight) return true;
    start = index + 1;
  }
}

bool _isLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

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

  final Map<String, Map<String, Object?>> _decryptedContent = {};

  // ── Public getters ─────────────────────────────────────────

  int get unreadCount => _cachedUnreadCount;

  bool get hasMore => _nextToken != null;

  Map<String, Object?>? decryptedContentFor(String eventId) =>
      _decryptedContent[eventId];

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
      final response = await _client.getNotifications(limit: 30);
      if (_disposed || gen != _fetchGeneration) return;
      _nextToken = response.nextToken;
      _grouped = await _groupByRoom(response.notifications);
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
      );
      if (_disposed || gen != _fetchGeneration) return;
      _nextToken = response.nextToken;

      // Merge new notifications into existing groups
      final all = <matrix_sdk.Notification>[];
      for (final group in _grouped) {
        all.addAll(group.notifications);
      }
      all.addAll(response.notifications);
      _grouped = await _groupByRoom(all);
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
      final response = await _client.getNotifications(limit: 30);
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
      _grouped = await _groupByRoom(all);
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
    unawaited(ApnsPushService.clearBadge());
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
    _decryptedContent.clear();
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

  // ── Mention detection ──────────────────────────────────────

  bool _isMention(matrix_sdk.Notification n) {
    final userId = _client.userID;
    if (userId == null) return false;

    final content =
        _decryptedContent[n.event.eventId] ?? n.event.content;

    final mentions = content['m.mentions'];
    if (mentions is Map) {
      final userIds = mentions['user_ids'];
      if (userIds is List && userIds.contains(userId)) return true;
    }

    final body = content['body'];
    if (body is String) {
      final lower = body.toLowerCase();
      if (lower.contains(userId.toLowerCase())) return true;
      final displayName = _client
          .getRoomById(n.roomId)
          ?.unsafeGetUserFromMemoryOrFallback(userId)
          .calcDisplayname();
      if (displayName != null &&
          displayName.length >= 2 &&
          _containsWord(lower, displayName.toLowerCase())) {
        return true;
      }
    }

    return false;
  }

  // ── Helpers ────────────────────────────────────────────────

  Future<Map<String, Object?>?> _tryDecrypt(matrix_sdk.Notification n) async {
    if (n.event.type != EventTypes.Encrypted) return null;
    final cached = _decryptedContent[n.event.eventId];
    if (cached != null) return cached;
    final room = _client.getRoomById(n.roomId);
    if (room == null) return null;
    try {
      final event = Event.fromMatrixEvent(n.event, room);
      final decrypted = await room.client.encryption
          ?.decryptRoomEvent(event)
          .timeout(const Duration(seconds: 3));
      if (decrypted != null) {
        _decryptedContent[n.event.eventId] = decrypted.content;
        return decrypted.content;
      }
    } catch (_) {}
    return null;
  }

  Future<List<NotificationGroup>> _groupByRoom(
      List<matrix_sdk.Notification> notifications,) async {
    final map = <String, List<matrix_sdk.Notification>>{};
    final order = <String>[];

    for (final n in notifications) {
      if (n.read) continue;
      final room = _client.getRoomById(n.roomId);
      if (room == null || room.membership != Membership.join) continue;
      await _tryDecrypt(n);
      if (_filter == InboxFilter.mentions && !_isMention(n)) continue;
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

import 'package:matrix/matrix.dart';

import '../services/preferences_service.dart';

/// Whether [text] contains [word] as a whole word (bounded by non-letter
/// characters or string edges). Avoids per-call RegExp compilation.
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

// ── Notification-level-aware unread count ───────────────────

/// Effective unread count filtered by the global notification level.
/// Shared between the room list UI and the OS notification service.
int effectiveUnreadCount(Room room, PreferencesService prefs) {
  switch (prefs.notificationLevel) {
    case NotificationLevel.all:
      return room.notificationCount;
    case NotificationLevel.off:
      return 0;
    case NotificationLevel.mentionsOnly:
      if (room.highlightCount > 0) return room.highlightCount;
      final body = room.lastEvent?.body.toLowerCase();
      if (body == null) return 0;
      for (final kw in prefs.notificationKeywords) {
        if (kw.isNotEmpty && body.contains(kw)) return 1;
      }
      return 0;
  }
}

/// Whether a specific message event should trigger an OS notification
/// under the current notification level and custom keywords.
///
/// For mention detection this checks whether the event body contains the
/// user's Matrix ID or display name, rather than relying on the room-level
/// [Room.highlightCount] which is stale across multiple events.
bool shouldNotifyForEvent({
  required String eventBody,
  required String? senderId,
  required String? ownUserId,
  required Room room,
  required PreferencesService prefs,
}) {
  // Never notify for own messages
  if (senderId == ownUserId) return false;

  switch (prefs.notificationLevel) {
    case NotificationLevel.off:
      return false;
    case NotificationLevel.all:
      return true;
    case NotificationLevel.mentionsOnly:
      final lower = eventBody.toLowerCase();
      // Check if the event mentions the current user by Matrix ID or display name.
      if (ownUserId != null && lower.contains(ownUserId.toLowerCase())) {
        return true;
      }
      final displayName = room.client.userID != null
          ? room
              .unsafeGetUserFromMemoryOrFallback(room.client.userID!)
              .calcDisplayname()
              .toLowerCase()
          : null;
      if (displayName != null &&
          displayName.length >= 2 &&
          _containsWord(lower, displayName)) {
        return true;
      }
      // Check custom keywords.
      for (final kw in prefs.notificationKeywords) {
        if (kw.isNotEmpty && lower.contains(kw)) return true;
      }
      return false;
  }
}

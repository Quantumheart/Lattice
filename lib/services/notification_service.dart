import 'dart:async';
import 'dart:io';

import 'package:desktop_notifications/desktop_notifications.dart' as dn;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

import '../utils/notification_filter.dart';
import 'matrix_service.dart';
import 'preferences_service.dart';

bool get _isLinux => !kIsWeb && Platform.isLinux;

/// Stable 31-bit positive integer hash for notification IDs.
/// Unlike [String.hashCode], this is deterministic across isolates and runs.
int _stableNotificationId(String roomId) {
  // FNV-1a 32-bit
  var hash = 0x811c9dc5;
  for (var i = 0; i < roomId.length; i++) {
    hash ^= roomId.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// Background service that listens to sync events and shows OS notifications.
///
/// This is a plain Dart class (not a ChangeNotifier) — it has no UI state.
/// Constructed in the widget tree and managed via start/stop lifecycle.
///
/// On Linux, uses `desktop_notifications` (D-Bus) directly for reliable
/// notification display and dismissal. On other platforms, uses
/// `flutter_local_notifications`.
class NotificationService {
  NotificationService({
    required this.matrixService,
    required this.preferencesService,
    @visibleForTesting FlutterLocalNotificationsPlugin? plugin,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _useLinux = plugin == null && _isLinux;

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final FlutterLocalNotificationsPlugin _plugin;
  final bool _useLinux;

  StreamSubscription<SyncUpdate>? _syncSub;
  bool _firstSyncDone = false;
  bool _disposed = false;
  final Set<String> _processingRooms = {};
  final Set<String> _notifiedInvites = {};

  /// Whether the app is currently in the foreground. Updated by the holder.
  bool isAppResumed = true;

  // ── Linux D-Bus notifications ─────────────────────────────────

  dn.NotificationsClient? _linuxClient;
  final Map<String, dn.Notification> _linuxNotifications = {};

  // ── Initialization ───────────────────────────────────────────

  Future<void> init() async {
    if (_useLinux) {
      _linuxClient = dn.NotificationsClient();
      debugPrint('[Lattice] NotificationService initialized (Linux D-Bus)');
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    debugPrint('[Lattice] NotificationService initialized');
  }

  // ── Start / stop listening ───────────────────────────────────

  void startListening() {
    _firstSyncDone = false;
    _syncSub?.cancel();
    _syncSub = matrixService.client.onSync.stream.listen(_onSync);
    debugPrint('[Lattice] NotificationService listening to sync stream');
  }

  void stopListening() {
    _syncSub?.cancel();
    _syncSub = null;
    _firstSyncDone = false;
    _notifiedInvites.clear();
  }

  // ── Sync handler ─────────────────────────────────────────────

  void _onSync(SyncUpdate sync) {
    // Skip the first sync (initial history catchup).
    if (!_firstSyncDone) {
      _firstSyncDone = true;
      return;
    }

    if (!preferencesService.osNotificationsEnabled) return;
    if (preferencesService.notificationLevel == NotificationLevel.off) return;

    // Process joined room events (messages).
    final joinedRooms = sync.rooms?.join;
    if (joinedRooms != null) {
      for (final entry in joinedRooms.entries) {
        // Room joined — allow re-invite notifications in the future.
        _notifiedInvites.remove(entry.key);
        final events = entry.value.timeline?.events;
        if (events == null || events.isEmpty) continue;
        final roomId = entry.key;
        if (_processingRooms.contains(roomId)) continue;
        _processRoomEvents(roomId, events).catchError((e) {
          debugPrint('[Lattice] Error processing room $roomId: $e');
        });
      }
    }

    // Room left/declined — allow re-invite notifications in the future.
    final leftRooms = sync.rooms?.leave;
    if (leftRooms != null) {
      for (final roomId in leftRooms.keys) {
        _notifiedInvites.remove(roomId);
      }
    }

    // Process new invites.
    final inviteRooms = sync.rooms?.invite;
    if (inviteRooms != null) {
      for (final entry in inviteRooms.entries) {
        final roomId = entry.key;
        if (_processingRooms.contains(roomId)) continue;
        _processInvite(roomId, entry.value).catchError((e) {
          debugPrint('[Lattice] Error processing invite $roomId: $e');
        });
      }
    }
  }

  Future<void> _processInvite(
    String roomId,
    InvitedRoomUpdate update,
  ) async {
    _processingRooms.add(roomId);
    try {
      if (_disposed) return;
      // Deduplicate: only notify once per invite room.
      if (_notifiedInvites.contains(roomId)) return;

      // Suppress when the app is in the foreground (matches message behavior).
      if (isAppResumed && !preferencesService.foregroundNotificationsEnabled) {
        return;
      }

      final client = matrixService.client;
      final room = client.getRoomById(roomId);

      // Respect per-room push rules.
      if (room?.pushRuleState == PushRuleState.dontNotify) return;

      final roomName = room?.getLocalizedDisplayname() ?? roomId;

      // Find who sent the invite from the invite state.
      String inviterName = 'Someone';
      final inviteEvents = update.inviteState;
      if (inviteEvents != null) {
        for (final event in inviteEvents) {
          if (event.type == EventTypes.RoomMember &&
              event.stateKey == client.userID) {
            inviterName = room
                    ?.unsafeGetUserFromMemoryOrFallback(event.senderId)
                    .calcDisplayname() ??
                event.senderId;
            break;
          }
        }
      }

      await _showNotification(
        roomId: roomId,
        title: roomName,
        senderName: inviterName,
        body: 'invited you to join',
      );
      _notifiedInvites.add(roomId);
    } finally {
      _processingRooms.remove(roomId);
    }
  }

  Future<void> _processRoomEvents(
    String roomId,
    List<MatrixEvent> events,
  ) async {
    _processingRooms.add(roomId);
    try {
      await _processRoomEventsInner(roomId, events);
    } finally {
      _processingRooms.remove(roomId);
    }
  }

  Future<void> _processRoomEventsInner(
    String roomId,
    List<MatrixEvent> events,
  ) async {
    if (_disposed) return;
    final client = matrixService.client;
    final room = client.getRoomById(roomId);
    if (room == null) return;

    // If any event is from the current user, they're active in this room —
    // clear any existing notification and stop processing.
    final hasOwnMessage = events.any((e) =>
        (e.type == EventTypes.Message || e.type == EventTypes.Encrypted) &&
        e.senderId == client.userID);
    if (hasOwnMessage) {
      cancelForRoom(roomId);
      return;
    }

    // Respect per-room push rules.
    if (room.pushRuleState == PushRuleState.dontNotify) return;

    // Suppress for the currently viewed room only when the app is visible,
    // unless the user has opted in to foreground notifications.
    if (matrixService.selectedRoomId == roomId &&
        isAppResumed &&
        !preferencesService.foregroundNotificationsEnabled) {
      return;
    }

    for (final matrixEvent in events) {
      if (matrixEvent.type != EventTypes.Message &&
          matrixEvent.type != EventTypes.Encrypted) {
        continue;
      }

      final event = Event.fromMatrixEvent(matrixEvent, room);
      String body;

      if (matrixEvent.type == EventTypes.Encrypted) {
        body = await _tryDecrypt(room, event);
      } else {
        body = event.body;
      }

      if (!shouldNotifyForEvent(
        eventBody: body,
        senderId: matrixEvent.senderId,
        ownUserId: client.userID,
        room: room,
        prefs: preferencesService,
      )) {
        continue;
      }

      if (_disposed) return;

      final senderName = room
          .unsafeGetUserFromMemoryOrFallback(matrixEvent.senderId)
          .calcDisplayname();

      await _showNotification(
        roomId: roomId,
        title: room.getLocalizedDisplayname(),
        senderName: senderName,
        body: body,
      );
    }
  }

  // ── Decryption ───────────────────────────────────────────────

  Future<String> _tryDecrypt(Room room, Event event) async {
    try {
      final decrypted = await room.client.encryption
          ?.decryptRoomEvent(event)
          .timeout(const Duration(seconds: 3));
      return decrypted?.body ?? 'Encrypted message';
    } catch (e) {
      debugPrint('[Lattice] Decryption failed for notification: $e');
      return 'Encrypted message';
    }
  }

  // ── Show notification ────────────────────────────────────────

  Future<void> _showNotification({
    required String roomId,
    required String title,
    required String senderName,
    required String body,
  }) async {
    if (_useLinux) {
      await _showLinuxNotification(
        roomId: roomId,
        title: title,
        senderName: senderName,
        body: body,
      );
      return;
    }

    final notificationId = _stableNotificationId(roomId);

    final androidDetails = AndroidNotificationDetails(
      'lattice_messages',
      'Messages',
      channelDescription: 'Chat message notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: preferencesService.notificationSoundEnabled,
      enableVibration: preferencesService.notificationVibrationEnabled,
    );

    final details = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      notificationId,
      title,
      '$senderName: $body',
      details,
      payload: roomId,
    );

    debugPrint('[Lattice] Notification shown for room $roomId');
  }

  Future<void> _showLinuxNotification({
    required String roomId,
    required String title,
    required String senderName,
    required String body,
  }) async {
    try {
      final notification = await _linuxClient!.notify(
        title,
        body: '$senderName: $body',
        replacesId: _linuxNotifications[roomId]?.id ?? 0,
        appName: 'Lattice',
        hints: [dn.NotificationHint.soundName('message-new-instant')],
      );
      notification.action.then((_) {
        if (_disposed) return;
        debugPrint('[Lattice] Linux notification tapped for room $roomId');
        matrixService.selectRoom(roomId);
      });
      _linuxNotifications[roomId] = notification;
      debugPrint(
          '[Lattice] Linux notification shown for room $roomId (id=${notification.id})');
    } catch (e) {
      debugPrint('[Lattice] Failed to show Linux notification: $e');
    }
  }

  // ── Notification tap ─────────────────────────────────────────

  void _onNotificationTap(NotificationResponse response) {
    final roomId = response.payload;
    if (roomId != null && roomId.isNotEmpty) {
      debugPrint('[Lattice] Notification tapped, selecting room $roomId');
      matrixService.selectRoom(roomId);
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────

  /// Dismiss the notification for a specific room.
  Future<void> cancelForRoom(String roomId) async {
    if (_useLinux) {
      final notification = _linuxNotifications.remove(roomId);
      if (notification != null) {
        try {
          await notification.close();
        } catch (e) {
          debugPrint('[Lattice] Failed to close Linux notification: $e');
        }
      }
      return;
    }
    final notificationId = _stableNotificationId(roomId);
    await _plugin.cancel(notificationId);
  }

  /// Dismiss all active notifications from the system tray.
  Future<void> cancelAll() async {
    if (_useLinux) {
      for (final notification in _linuxNotifications.values) {
        try {
          await notification.close();
        } catch (e) {
          debugPrint('[Lattice] Failed to close Linux notification: $e');
        }
      }
      _linuxNotifications.clear();
      debugPrint('[Lattice] All Linux notifications cancelled');
      return;
    }
    await _plugin.cancelAll();
    debugPrint('[Lattice] All notifications cancelled');
  }

  void dispose() {
    _disposed = true;
    stopListening();
    // Fire-and-forget but log failures — cancelAll() is async but dispose()
    // must be synchronous to match the widget lifecycle.
    cancelAll().catchError((e) {
      debugPrint('[Lattice] Error cancelling notifications during dispose: $e');
    });
    _linuxClient?.close();
  }
}

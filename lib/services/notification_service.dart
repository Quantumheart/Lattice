import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

import '../utils/notification_filter.dart';
import 'matrix_service.dart';
import 'preferences_service.dart';

/// Background service that listens to sync events and shows OS notifications.
///
/// This is a plain Dart class (not a ChangeNotifier) — it has no UI state.
/// Constructed in the widget tree and managed via start/stop lifecycle.
class NotificationService {
  NotificationService({
    required this.matrixService,
    required this.preferencesService,
    @visibleForTesting FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final FlutterLocalNotificationsPlugin _plugin;

  StreamSubscription<SyncUpdate>? _syncSub;
  bool _firstSyncDone = false;
  final Set<String> _processingRooms = {};

  // ── Initialization ───────────────────────────────────────────

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
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

    final joinedRooms = sync.rooms?.join;
    if (joinedRooms == null) return;

    for (final entry in joinedRooms.entries) {
      final events = entry.value.timeline?.events;
      if (events == null || events.isEmpty) continue;
      // Skip rooms already being processed to avoid duplicate notifications.
      final roomId = entry.key;
      if (_processingRooms.contains(roomId)) continue;
      _processRoomEvents(roomId, events);
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
    final client = matrixService.client;
    final room = client.getRoomById(roomId);
    if (room == null) return;

    // Respect per-room push rules.
    if (room.pushRuleState == PushRuleState.dontNotify) return;

    // Suppress for the currently viewed room unless foreground enabled.
    if (matrixService.selectedRoomId == roomId &&
        !preferencesService.foregroundNotificationsEnabled) {
      return;
    }

    for (final matrixEvent in events) {
      if (matrixEvent.type != EventTypes.Message &&
          matrixEvent.type != EventTypes.Encrypted) {
        continue;
      }
      if (matrixEvent.senderId == client.userID) continue;

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
    final notificationId = roomId.hashCode & 0x7FFFFFFF;

    final androidDetails = AndroidNotificationDetails(
      'lattice_messages',
      'Messages',
      channelDescription: 'Chat message notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: preferencesService.notificationSoundEnabled,
      enableVibration: preferencesService.notificationVibrationEnabled,
    );

    const linuxDetails = LinuxNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      linux: linuxDetails,
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

  // ── Notification tap ─────────────────────────────────────────

  void _onNotificationTap(NotificationResponse response) {
    final roomId = response.payload;
    if (roomId != null && roomId.isNotEmpty) {
      debugPrint('[Lattice] Notification tapped, selecting room $roomId');
      matrixService.selectRoom(roomId);
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────

  /// Dismiss all active notifications from the system tray.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    debugPrint('[Lattice] All notifications cancelled');
  }

  void dispose() {
    stopListening();
  }
}

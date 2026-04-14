import 'dart:async';

import 'package:desktop_notifications/desktop_notifications.dart' as dn;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/utils/media_auth.dart';
import 'package:lattice/core/utils/media_cache_io.dart'
    if (dart.library.js_interop) 'package:lattice/core/utils/media_cache_web.dart';
import 'package:lattice/core/utils/notification_filter.dart';
import 'package:lattice/core/utils/platform_info.dart';
import 'package:lattice/features/calling/models/call_constants.dart';
import 'package:lattice/features/notifications/models/notification_constants.dart';
import 'package:lattice/features/notifications/services/web_notifications.dart';
import 'package:lattice/features/notifications/services/windows_com_register.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

bool get _isLinux => isNativeLinux;

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
    this.router,
    @visibleForTesting FlutterLocalNotificationsPlugin? plugin,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _useLinux = plugin == null && _isLinux;

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final GoRouter? router;
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
    if (kIsWeb) {
      debugPrint('[Lattice] NotificationService initialized (Web)');
      return;
    }
    if (_useLinux) {
      _linuxClient = dn.NotificationsClient();
      debugPrint('[Lattice] NotificationService initialized (Linux D-Bus)');
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      
    );

    const windowsSettings = WindowsInitializationSettings(
      appName: NotificationChannel.appName,
      appUserModelId: NotificationChannel.appId,
      guid: NotificationChannel.windowsGuid,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      windows: windowsSettings,
    );

    if (isNativeWindows) {
      await registerWindowsComServer();
    }

    final initialized = await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    if (initialized != true) {
      debugPrint(
        '[Lattice] Warning: Notification plugin initialization returned $initialized',
      );
      return;
    }

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
    unawaited(_syncSub?.cancel());
    _syncSub = matrixService.client.onSync.stream.listen(_onSync);
    debugPrint('[Lattice] NotificationService listening to sync stream');
  }

  void stopListening() {
    unawaited(_syncSub?.cancel());
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
        unawaited(_processRoomEvents(roomId, events).catchError((Object e) {
          debugPrint('[Lattice] Error processing room $roomId: $e');
        },),);
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
        unawaited(_processInvite(roomId, entry.value).catchError((Object e) {
          debugPrint('[Lattice] Error processing invite $roomId: $e');
        },),);
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
      var inviterName = NotificationText.fallbackInviterName;
      Uri? inviterAvatarUrl;
      final inviteEvents = update.inviteState;
      if (inviteEvents != null) {
        for (final event in inviteEvents) {
          if (event.type == EventTypes.RoomMember &&
              event.stateKey == client.userID) {
            final inviter =
                room?.unsafeGetUserFromMemoryOrFallback(event.senderId);
            inviterName = inviter?.calcDisplayname() ?? event.senderId;
            inviterAvatarUrl = inviter?.avatarUrl;
            break;
          }
        }
      }

      String? avatarPath;
      String? avatarUrl;
      if (kIsWeb && inviterAvatarUrl != null) {
        try {
          final uri = await inviterAvatarUrl.getThumbnailUri(
            client,
            width: 128,
            height: 128,
          );
          final rawUrl = uri.toString();
          final headers = mediaAuthHeaders(client, rawUrl);
          avatarUrl = await resolveWebAvatarUrl(rawUrl, headers) ?? rawUrl;
        } catch (_) {}
      } else if (_useLinux) {
        avatarPath =
            await downloadAvatarToTemp(client, inviterAvatarUrl, inviterName);
      }

      await _showNotification(
        roomId: roomId,
        title: roomName,
        senderName: inviterName,
        body: NotificationText.inviteBody,
        avatarPath: avatarPath,
        avatarUrl: avatarUrl,
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
    if (isNativeIOS && preferencesService.apnsPushEnabled) return;
    final client = matrixService.client;
    final room = client.getRoomById(roomId);
    if (room == null) return;

    // If any event is from the current user, they're active in this room —
    // clear any existing notification and stop processing.
    final hasOwnMessage = events.any((e) =>
        (e.type == EventTypes.Message || e.type == EventTypes.Encrypted) &&
        e.senderId == client.userID,);
    if (hasOwnMessage) {
      await cancelForRoom(roomId);
      return;
    }

    // Respect per-room push rules.
    if (room.pushRuleState == PushRuleState.dontNotify) return;

    // Suppress for the currently viewed room only when the app is visible,
    // unless the user has opted in to foreground notifications.
    if (matrixService.selection.selectedRoomId == roomId &&
        isAppResumed &&
        !preferencesService.foregroundNotificationsEnabled) {
      return;
    }

    final lowerUserId = client.userID?.toLowerCase();
    final lowerDisplayName = client.userID != null
        ? room
            .unsafeGetUserFromMemoryOrFallback(client.userID!)
            .calcDisplayname()
            .toLowerCase()
        : null;

    final notifiable = <(String senderName, String body, Uri? avatarUrl)>[];

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
        cachedLowerUserId: lowerUserId,
        cachedLowerDisplayName: lowerDisplayName,
      )) {
        continue;
      }

      if (_disposed) return;

      final sender =
          room.unsafeGetUserFromMemoryOrFallback(matrixEvent.senderId);
      notifiable.add((sender.calcDisplayname(), body, sender.avatarUrl));
    }

    if (notifiable.isEmpty) return;

    String? avatarPath;
    String? avatarUrl;
    if (kIsWeb && notifiable.first.$3 != null) {
      try {
        final uri = await notifiable.first.$3!.getThumbnailUri(
          client,
          width: 128,
          height: 128,
        );
        final rawUrl = uri.toString();
        final headers = mediaAuthHeaders(client, rawUrl);
        avatarUrl = await resolveWebAvatarUrl(rawUrl, headers) ?? rawUrl;
      } catch (_) {}
    } else if (_useLinux) {
      avatarPath = await downloadAvatarToTemp(
        client,
        notifiable.first.$3,
        notifiable.first.$1,
      );
    }

    final roomName = room.getLocalizedDisplayname();

    if (notifiable.length == 1) {
      await _showNotification(
        roomId: roomId,
        title: roomName,
        senderName: notifiable.first.$1,
        body: notifiable.first.$2,
        avatarPath: avatarPath,
        avatarUrl: avatarUrl,
      );
    } else {
      final lines = <String>[];
      for (final (name, body, _) in notifiable.take(3)) {
        lines.add(NotificationText.senderBody(name, body));
      }
      if (notifiable.length > 3) {
        lines.add(NotificationText.moreMessages(notifiable.length - 3));
      }
      await _showNotification(
        roomId: roomId,
        title: NotificationText.groupTitle(roomName, notifiable.length),
        senderName: '',
        body: lines.join('\n'),
        avatarPath: avatarPath,
        avatarUrl: avatarUrl,
        isGrouped: true,
      );
    }
  }

  // ── Decryption ───────────────────────────────────────────────

  Future<String> _tryDecrypt(Room room, Event event) async {
    try {
      final decrypted = await room.client.encryption
          ?.decryptRoomEvent(event)
          .timeout(const Duration(seconds: 3));
      if (decrypted != null && callEventTypes.contains(decrypted.type)) {
        return _formatCallEvent(decrypted);
      }
      return decrypted?.body ?? NotificationText.encryptedMessage;
    } catch (e) {
      debugPrint('[Lattice] Decryption failed for notification: $e');
      return NotificationText.encryptedMessage;
    }
  }

  static String _formatCallEvent(Event event) {
    final sender = event.senderFromMemoryOrFallback.calcDisplayname();
    switch (event.type) {
      case kCallInvite:
        return NotificationText.callStarted(sender);
      case kCallAnswer:
        return NotificationText.callAnswered(sender);
      case kCallReject:
        return NotificationText.callDeclined(sender);
      case kCallHangup:
        final reason = event.content.tryGet<String>('reason');
        if (reason == kHangupInviteTimeout) {
          return NotificationText.callMissed(sender);
        }
        return NotificationText.callEnded;
      default:
        return NotificationText.callEnded;
    }
  }

  // ── Avatar download ─────────────────────────────────────────

  @visibleForTesting
  Future<String?> downloadAvatarToTemp(
    Client client,
    Uri? avatarUrl,
    String userId,
  ) async {
    if (avatarUrl == null) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final sanitized = userId.replaceAll(RegExp('[^a-zA-Z0-9]'), '_');
      final path = '${tempDir.path}/${NotificationChannel.avatarTempPrefix}$sanitized.png';
      final file = File(path);
      if (file.existsSync()) return path;

      final uri = await avatarUrl.getThumbnailUri(
        client,
        width: 128,
        height: 128,
      );
      final headers = mediaAuthHeaders(client, uri.toString());
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return path;
      }
    } catch (e) {
      debugPrint('[Lattice] Failed to download avatar for $userId: $e');
    }
    return null;
  }

  // ── Show notification ────────────────────────────────────────

  Future<void> _showNotification({
    required String roomId,
    required String title,
    required String senderName,
    required String body,
    String? avatarPath,
    String? avatarUrl,
    bool isGrouped = false,
  }) async {
    if (kIsWeb) {
      final unreadCount = matrixService.client.rooms
          .where((r) => r.notificationCount > 0)
          .fold<int>(0, (sum, r) => sum + r.notificationCount);
      showWebNotification(
        title: title,
        body: senderName.isNotEmpty
            ? NotificationText.senderBody(senderName, body)
            : body,
        icon: avatarUrl,
        tag: roomId,
        roomId: roomId,
        silent: !preferencesService.notificationSoundEnabled,
        unreadCount: unreadCount,
      );
      if (unreadCount == 0) clearWebAppBadge();
      return;
    }
    if (_useLinux) {
      await _showLinuxNotification(
        roomId: roomId,
        title: title,
        senderName: senderName,
        body: body,
        avatarPath: avatarPath,
        isGrouped: isGrouped,
      );
      return;
    }

    final notificationId = _stableNotificationId(roomId);

    final androidDetails = AndroidNotificationDetails(
      NotificationChannel.androidChannelId,
      NotificationChannel.androidChannelName,
      channelDescription: NotificationChannel.androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: preferencesService.notificationSoundEnabled,
      enableVibration: preferencesService.notificationVibrationEnabled,
      groupKey: NotificationChannel.androidGroupKey,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: preferencesService.notificationSoundEnabled,
    );

    final windowsDetails = WindowsNotificationDetails(
      audio: preferencesService.notificationSoundEnabled
          ? WindowsNotificationAudio.preset(
              sound: WindowsNotificationSound.im,
            )
          : WindowsNotificationAudio.silent(),
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      windows: windowsDetails,
    );

    final displayBody =
        isGrouped ? body : NotificationText.senderBody(senderName, body);

    await _plugin.show(
      id: notificationId,
      title: title,
      body: displayBody,
      notificationDetails: details,
      payload: roomId,
    );

    debugPrint('[Lattice] Notification shown for room $roomId');
  }

  Future<void> _showLinuxNotification({
    required String roomId,
    required String title,
    required String senderName,
    required String body,
    String? avatarPath,
    bool isGrouped = false,
  }) async {
    try {
      final hints = <dn.NotificationHint>[
        dn.NotificationHint.soundName(NotificationChannel.linuxSoundName),
        dn.NotificationHint.desktopEntry(NotificationChannel.linuxDesktopEntry),
        dn.NotificationHint.category(dn.NotificationCategory.im()),
        if (avatarPath != null) dn.NotificationHint.imagePath(avatarPath),
      ];

      final displayBody =
          isGrouped ? body : NotificationText.senderBody(senderName, body);

      final notification = await _linuxClient!.notify(
        title,
        body: displayBody,
        replacesId: _linuxNotifications[roomId]?.id ?? 0,
        appName: NotificationChannel.appName,
        appIcon: NotificationChannel.linuxAppIcon,
        hints: hints,
        actions: [
          const dn.NotificationAction('default', ''),
          const dn.NotificationAction('reply', NotificationText.replyAction),
          const dn.NotificationAction('mark_read', NotificationText.markAsReadAction),
        ],
      );
      unawaited(notification.action.then((actionKey) {
        if (_disposed) return;
        final client = matrixService.client;
        final room = client.getRoomById(roomId);
        if (actionKey == 'mark_read') {
          debugPrint(
            '[Lattice] Linux notification mark_read for room $roomId',
          );
          final lastEventId = room?.lastEvent?.eventId;
          if (room != null && lastEventId != null) {
            unawaited(
              room.setReadMarker(lastEventId, mRead: lastEventId).catchError((Object e) {
                debugPrint('[Lattice] Failed to mark room as read: $e');
              }),
            );
          }
          _linuxNotifications.remove(roomId);
          unawaited(
            notification.close().catchError((Object e) {
              debugPrint('[Lattice] Failed to close notification: $e');
            }),
          );
        } else {
          debugPrint(
            '[Lattice] Linux notification tapped for room $roomId',
          );
          navigateToRoom(roomId);
        }
      }),);
      _linuxNotifications[roomId] = notification;
      debugPrint(
        '[Lattice] Linux notification shown for room $roomId (id=${notification.id})',
      );
    } catch (e) {
      debugPrint('[Lattice] Failed to show Linux notification: $e');
    }
  }

  // ── Notification tap ─────────────────────────────────────────

  void navigateToRoom(String roomId) {
    if (router != null) {
      router!.goNamed(Routes.room, pathParameters: {'roomId': roomId});
    } else {
      matrixService.selection.selectRoom(roomId);
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    final roomId = response.payload;
    if (roomId != null && roomId.isNotEmpty) {
      debugPrint('[Lattice] Notification tapped, selecting room $roomId');
      navigateToRoom(roomId);
    }
  }

  // ── Push notification entry point ───────────────────────────

  Future<void> showPushNotification({
    required String roomId,
    required String title,
    required String body,
    String senderName = '',
  }) async {
    await _showNotification(
      roomId: roomId,
      title: title,
      senderName: senderName,
      body: body,
    );
  }

  // ── Cleanup ──────────────────────────────────────────────────

  /// Dismiss the notification for a specific room.
  Future<void> cancelForRoom(String roomId) async {
    if (kIsWeb) {
      closeWebNotification(roomId);
      clearWebAppBadge();
      return;
    }
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
    await _plugin.cancel(id: notificationId);
  }

  /// Dismiss all active notifications from the system tray.
  Future<void> cancelAll() async {
    if (kIsWeb) {
      closeAllWebNotifications();
      clearWebAppBadge();
      return;
    }
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
    unawaited(cancelAll().catchError((Object e) {
      debugPrint('[Lattice] Error cancelling notifications during dispose: $e');
    },),);
    unawaited(_linuxClient?.close());
  }
}

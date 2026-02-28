# Plan: Implement Windows Notifications for Lattice

## Current State

Lattice already has a robust notification system in `lib/services/notification_service.dart` with two backends:
- **Linux**: Uses `desktop_notifications` (D-Bus) via a dedicated code path (`_useLinux`)
- **Android/iOS/macOS**: Uses `flutter_local_notifications` (v18.0.1)
- **Windows**: **Not configured** — the `init()` method only sets up Android and Darwin settings, and `_showNotification()` only provides Android and Darwin notification details. Windows falls through to the `flutter_local_notifications` path but without proper initialization, so notifications silently fail.

The notification infrastructure (sync listening, event filtering, preferences, lifecycle management) is fully platform-agnostic and requires no changes.

## Approach

**Extend the existing `flutter_local_notifications` integration to support Windows.** This package (already a dependency at v18.0.1) has built-in Windows support via C++/WinRT Toast Notifications. This is the lowest-friction approach — it keeps the same architecture and requires only adding Windows-specific configuration to two methods.

### Known Limitation: MSIX Packaging

Windows only allows apps with **package identity** (MSIX-packaged) to cancel/retrieve previously shown notifications. Without MSIX packaging:
- `cancel()` is a no-op (notifications still auto-dismiss when tapped or expired)
- `getActiveNotifications()` returns empty
- `show()` works fine for displaying notifications

This is an acceptable tradeoff for initial implementation. MSIX packaging can be added later as a separate task.

## Implementation Steps

### Step 1: Add Windows initialization settings in `NotificationService.init()`

**File:** `lib/services/notification_service.dart`

Add `WindowsInitializationSettings` to the `InitializationSettings` constructor in the `init()` method:

```dart
const windowsSettings = WindowsInitializationSettings(
  appName: 'Lattice',
  appUserModelId: 'dev.lattice.app',
  guid: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',  // generate a real GUID
);

const settings = InitializationSettings(
  android: androidSettings,
  iOS: darwinSettings,
  macOS: darwinSettings,
  windows: windowsSettings,
);
```

This enables `flutter_local_notifications` to initialize its Windows backend and register the app for toast notifications.

### Step 2: Add Windows notification details in `_showNotification()`

**File:** `lib/services/notification_service.dart`

Add `WindowsNotificationDetails` to the `NotificationDetails` constructor:

```dart
const windowsDetails = WindowsNotificationDetails();

final details = NotificationDetails(
  android: androidDetails,
  iOS: darwinDetails,
  macOS: darwinDetails,
  windows: windowsDetails,
);
```

The default `WindowsNotificationDetails()` provides a standard toast notification, which is appropriate for chat messages.

### Step 3: Document the `cancelForRoom()` MSIX limitation

**File:** `lib/services/notification_service.dart`

Add a doc comment to `cancelForRoom()` noting that on Windows without MSIX packaging, `cancel()` is a no-op. The existing code path is otherwise correct — it already falls through to `_plugin.cancel(notificationId)` for non-Linux platforms.

### Step 4: Add Windows platform check for notification sound preference

**File:** `lib/services/notification_service.dart`

The `AndroidNotificationDetails` has `playSound` and `enableVibration` — these don't apply to Windows. The `WindowsNotificationDetails` has its own audio configuration. Wire up the `notificationSoundEnabled` preference to the Windows details if the API supports it, or leave defaults (Windows toast notifications play the system default sound).

### Step 5: Update tests

**File:** `test/services/notification_service_test.dart`

The existing tests use `MockFlutterLocalNotificationsPlugin` and verify `show()` calls. These tests already exercise the non-Linux path (since tests don't run on Linux by default). No new test logic is needed because the Windows changes are purely configuration — the same `_plugin.show()` and `_plugin.cancel()` calls are made. However, verify that:
- The `init()` method works with Windows settings (the mock already accepts any `InitializationSettings`)
- No regressions in existing tests

### Step 6: Verify Windows runner configuration

**File:** `windows/flutter/generated_plugins.cmake`

Confirm that `flutter_local_notifications` is listed in the generated plugins. Since it's already a dependency in `pubspec.yaml`, running `flutter pub get` should auto-register it. If not listed, `flutter pub get` needs to be re-run.

## Files Changed

| File | Change |
|------|--------|
| `lib/services/notification_service.dart` | Add `WindowsInitializationSettings` in `init()`, add `WindowsNotificationDetails` in `_showNotification()`, add doc comment about MSIX limitation |
| `test/services/notification_service_test.dart` | Verify no regressions (may need minor updates if `InitializationSettings` validation changes) |

## Files NOT Changed

- `pubspec.yaml` — `flutter_local_notifications` already included
- `lib/main.dart` — notification lifecycle management is platform-agnostic
- `lib/utils/notification_filter.dart` — filtering logic is platform-agnostic
- `lib/services/preferences_service.dart` — preferences are platform-agnostic
- `windows/` native code — `flutter_local_notifications` handles native setup via its plugin

## Risk Assessment

- **Low risk**: Changes are additive configuration only — no behavioral changes on existing platforms
- **MSIX limitation**: `cancelForRoom()` won't dismiss Windows notifications without MSIX packaging, but notifications still display and auto-dismiss. Users can dismiss manually.
- **Testing**: Existing test suite covers the `flutter_local_notifications` code path used by Windows

## Future Work (Out of Scope)

- MSIX packaging for full cancel/retrieval support
- Windows-specific notification actions (reply buttons, inline responses)
- Notification grouping for Windows Action Center
- Badge count on Windows taskbar

# Web Deployment Blockers

Analysis of blockers preventing Lattice from deploying to Flutter Web.

## Critical Blockers (compilation/startup failures)

### 1. `dart:io` usage across 9 files

`dart:io` is not available in browsers. These files will fail to compile for web:

- `lib/core/services/client_factory.dart` — `Platform` checks, FFI init
- `lib/core/services/matrix_service.dart` — `FlutterSecureStorage` (indirect)
- `lib/features/auth/services/sso_callback_server.dart` — `HttpServer`, localhost binding
- `lib/features/auth/services/recaptcha_server.dart` — `HttpServer`, localhost binding
- `lib/features/auth/widgets/registration_controller.dart` — `dart:io` import
- `lib/features/chat/services/opengraph_service.dart` — `InternetAddress.lookup()` DNS resolution
- `lib/features/notifications/services/notification_service.dart` — `Platform.isLinux`
- `lib/features/rooms/widgets/room_tile.dart` — `Platform.isLinux/Windows/macOS`
- `lib/shared/widgets/full_image_view.dart` — `File().writeAsBytes()`

### 2. SQLite database — no web support

`client_factory.dart` uses `sqflite_common_ffi` and `sqflite`, neither of which work on web. The Matrix SDK requires a database for chat history, room state, and encrypted session data. Would need to swap to an IndexedDB-based implementation.

### 3. `flutter_secure_storage` — no web support

Used in `matrix_service.dart`, `client_manager.dart`, and `session_backup.dart` to persist access tokens, user IDs, homeserver URLs, and device IDs. Would need a web alternative (e.g., encrypted `localStorage` or `sessionStorage`).

### 4. Localhost HTTP servers for auth flows

`SsoCallbackServer` and `RecaptchaServer` bind to `127.0.0.1` to handle OAuth/reCAPTCHA callbacks. Browsers cannot create HTTP servers. These need to be replaced with redirect-based flows.

### 5. `path_provider` — no web support

Used in `client_factory.dart` to get `getApplicationSupportDirectory()` for the database path. No file system directories exist on web.

## High Priority Blockers (runtime failures)

### 6. Native isolates for crypto

`client_factory.dart` uses `NativeImplementationsIsolate(compute, ...)` for encryption. Web doesn't support true Dart isolates — would need web worker alternatives.

### 7. `desktop_notifications` — no web support

Linux D-Bus notifications in `notification_service.dart`. Would need the Web Notifications API instead.

### 8. File download via `dart:io File`

`full_image_view.dart` writes bytes to disk with `File(path).writeAsBytes()`. Web requires blob URLs and anchor-tag download triggers.

### 9. `image_picker` — no web support

Used in `avatar_edit_overlay.dart` for camera/gallery access. Would need HTML file input via the web file API.

## Medium Priority Issues

### 10. `file_picker` — partial web support

Used in `file_send_handler.dart` and `full_image_view.dart`. The web API is limited — `saveFile()` doesn't work the same way.

### 11. `dynamic_color` — partial web support

Material You dynamic theming has no OS-level color source on web.

## Dependency Web Support Summary

| Package | Web Support | Severity |
|---------|-------------|----------|
| `sqflite` / `sqflite_common_ffi` | No | Critical |
| `flutter_secure_storage` | No | Critical |
| `path_provider` | No | Critical |
| `desktop_notifications` | No | High |
| `image_picker` | No | High |
| `file_picker` | Partial | Medium |
| `flutter_local_notifications` | Partial | Medium |
| `dynamic_color` | Partial | Low |
| `shared_preferences` | Yes | OK |
| `url_launcher` | Yes | OK |

## Remediation Steps

1. **Conditional imports** — use `stub`/`web`/`native` pattern for all 9 `dart:io` files
2. **Database swap** — IndexedDB-backed storage for web
3. **Auth flow redesign** — redirect-based SSO/reCAPTCHA instead of localhost servers
4. **Secure storage abstraction** — `localStorage` or encrypted web storage fallback
5. **File I/O abstraction** — blob URLs for downloads, HTML file input for uploads
6. **Platform detection** — replace `dart:io Platform` with `kIsWeb` + `defaultTargetPlatform`

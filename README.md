# Lattice

A modern, cross-platform [Matrix](https://matrix.org) chat client built with Flutter. Lattice delivers end-to-end encrypted messaging with adaptive layouts that feel native on every device — from phones to desktops.

## Features

### Messaging
- Real-time message timeline with infinite scroll and contextual date headers
- Message reactions with emoji picker and quick-react bar
- Pin, reply, edit, and delete messages
- Rich text rendering with HTML support and syntax-highlighted code blocks
- File and image sharing with upload progress tracking
- Read receipts and typing indicators
- Full-text search across rooms

### End-to-End Encryption
- Cross-signing device verification (emoji SAS)
- Secure key backup (SSSS) with recovery key generation
- Automatic key recovery on startup via secure storage
- User-interactive authentication with cached password (5-minute TTL)

### Spaces & Organization
- Discord/Slack-style vertical space rail with icon avatars
- Room list with live search filtering
- Favorites, direct messages, groups, and unread categories
- Space hierarchy navigation
- Room creation, invites, and admin settings

### Adaptive Layout
Lattice automatically adjusts its layout to fit the screen:

| Width | Layout |
| --- | --- |
| < 720 px | Bottom nav + stack navigation (mobile) |
| 720–1100 px | Space rail + room list sidebar (tablet) |
| ≥ 1100 px | Space rail + room list + chat pane (desktop) |

### Notifications
- Native OS notifications (D-Bus on Linux, platform APIs elsewhere)
- Per-room notification levels: all messages, mentions only, or muted
- Smart dismissal when a room is already selected

### Theming
- Material You dynamic color theming extracted from system palette
- Light, dark, and system-follow modes
- Configurable message density (compact / default / comfortable)

### Multi-Account & Devices
- Device management with verification status
- Device renaming and remote sign-out

## Platforms

Android, iOS, macOS, Linux, Windows, and Web.

## Getting Started

### Prerequisites

- Flutter 3.16+ (stable channel)
- Dart 3.1+

### Setup

```bash
git clone https://github.com/your-org/lattice.git
cd lattice
flutter pub get
flutter run            # default device
flutter run -d linux   # Linux desktop
flutter run -d chrome  # Web
flutter run -d macos   # macOS
```

### Running Tests

```bash
# Generate mocks (required before first test run or when @GenerateMocks change)
dart run build_runner build --delete-conflicting-outputs

# Run all tests
flutter test

# Run a single test file
flutter test test/services/matrix_service_test.dart
```

### Building a Release

```bash
flutter build linux --release
```

The release binary is output to `build/linux/x64/release/bundle/`.

## Architecture

Lattice is organized into four layers:

```
lib/
├── main.dart                     # App entry, Provider setup, dynamic color
├── theme/
│   └── lattice_theme.dart        # Material You theme (light + dark)
├── services/
│   ├── matrix_service.dart       # Core state (ChangeNotifier via Provider)
│   │   └── mixins/
│   │       ├── auth_mixin.dart         # Login, registration, SSO
│   │       ├── chat_backup_mixin.dart  # E2EE key backup & auto-unlock
│   │       ├── selection_mixin.dart    # Room/space selection
│   │       ├── sync_mixin.dart         # Matrix sync lifecycle
│   │       └── uia_mixin.dart          # User-interactive auth
│   ├── notification_service.dart # OS notification delivery
│   ├── preferences_service.dart  # User settings persistence
│   └── client_manager.dart       # Multi-account support
├── screens/
│   ├── home_shell.dart           # Adaptive 3-column layout shell
│   ├── chat_screen.dart          # Message timeline + compose bar
│   ├── login_screen.dart         # Authentication
│   ├── settings_screen.dart      # Account & preferences
│   └── ...
└── widgets/                      # 85+ reusable UI components
    ├── chat/                     # Message bubbles, compose bar, reactions, pins
    ├── bootstrap_*.dart          # E2EE setup dialog & views
    ├── space_rail.dart           # Vertical space icon rail
    ├── room_list.dart            # Searchable room list
    └── ...
```

**State management** — A single `MatrixService` (ChangeNotifier) is provided at the app root via Provider. It wraps the Matrix SDK client and is composed of five focused mixins for auth, sync, selection, encryption, and UIA.

**E2EE** — Encryption is separated into three layers: `BootstrapController` (state machine), `BootstrapDialog` (modal orchestration), and `BootstrapViews` (stateless UI). See [`docs/e2ee-flow.md`](docs/e2ee-flow.md) for state machine diagrams and detailed flow documentation.

## Key Dependencies

| Package | Purpose |
| --- | --- |
| [`matrix`](https://pub.dev/packages/matrix) | Matrix protocol SDK |
| [`provider`](https://pub.dev/packages/provider) | State management |
| [`dynamic_color`](https://pub.dev/packages/dynamic_color) | Material You palette extraction |
| [`flutter_vodozemac`](https://pub.dev/packages/flutter_vodozemac) | E2EE encryption (Olm/Megolm) |
| [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) | Encrypted credential storage |
| [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) | Native OS notifications |
| [`emoji_picker_flutter`](https://pub.dev/packages/emoji_picker_flutter) | Emoji selection |
| [`cached_network_image`](https://pub.dev/packages/cached_network_image) | Avatar & image caching |
| [`sqflite`](https://pub.dev/packages/sqflite) | SQLite database |

## CI/CD

GitHub Actions runs on every push and PR to `master`:

1. **Analyze** — `flutter analyze` (lint checks)
2. **Test** — Mock generation + full test suite
3. **Build** — Linux x64 release build

Pushing a `v*` tag triggers an automated GitHub Release with a bundled `lattice-linux-x64.tar.gz`.

## Contributing

This project uses **semantic commits**:

```
feat: add message pinning support
fix: resolve timeline sync race condition
refactor: extract bubble styling into theme
test: add matrix_service unit tests
docs: update architecture diagram
chore: bump matrix SDK to 6.1.1
```

## License

MIT

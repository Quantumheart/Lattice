# Lattice — A Flutter Matrix Client

A modern, adaptive Matrix chat client built with Flutter and the `matrix` Dart SDK. Supports multiple layouts.

## Architecture

```
lib/
├── main.dart                 # App entry, providers, dynamic color
├── theme/
│   └── lattice_theme.dart    # Material You theme (light + dark)
├── services/
│   └── matrix_service.dart   # Matrix SDK wrapper (login, sync, state)
├── screens/
│   ├── login_screen.dart     # Authentication screen
│   ├── home_shell.dart       # Adaptive layout shell (rail + list + chat)
│   ├── chat_screen.dart      # Message timeline + compose bar
│   └── settings_screen.dart  # Account & preferences
└── widgets/
    ├── space_rail.dart       # Vertical space icon rail (desktop)
    ├── room_list.dart        # Searchable room list
    ├── room_avatar.dart      # Room avatar with initial fallback
    └── message_bubble.dart   # Chat message bubble
```

## Layouts

Lattice supports multiple adaptive layouts:

| Width          | Layout                                         |
| -------------- | ---------------------------------------------- |
| < 720px        | Bottom nav bar + stack navigation (mobile)     |
| 720–1100px     | Space rail + room list + placeholder           |
| ≥ 1100px       | Space rail + room list + chat pane (3-column)  |

### Key Features

- **Vertical icon rail** for spaces (Discord/Slack-style)
- **Material You** dynamic color theming
- **Adaptive master-detail** with animated transitions
- **Unified search** across rooms
- **Secure credential storage** via flutter_secure_storage

## Getting Started

### Prerequisites

- Flutter 3.16+ (stable)
- Dart 3.1+

### Setup

```bash
# Clone the project
cd lattice

# Install dependencies
flutter pub get

# Run on your target platform
flutter run                  # Default device
flutter run -d chrome        # Web
flutter run -d macos         # macOS
flutter run -d linux         # Linux
```

### Configuration

The app connects to any Matrix homeserver. Enter your homeserver URL,
username, and password on the login screen.

Default: `matrix.org`

## Commit Convention

This project uses **semantic commits**:

```
feat: add hat wobble
fix: resolve timeline sync race condition
refactor: extract bubble styling into theme
style: format imports
docs: update README with architecture diagram
test: add matrix_service unit tests
chore: bump matrix SDK to 0.37.0
```

## Dependencies

| Package                  | Purpose                          |
| ------------------------ | -------------------------------- |
| `matrix`                 | Matrix protocol SDK              |
| `provider`               | State management                 |
| `cached_network_image`   | Avatar caching                   |
| `flutter_secure_storage` | Credential persistence           |
| `dynamic_color`          | Material You palette extraction  |
| `animations`             | Page transition animations       |
| `url_launcher`           | External link handling           |

## License

MIT

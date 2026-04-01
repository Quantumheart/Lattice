# Lattice

A modern, adaptive Matrix chat client built with Flutter. Supports end-to-end encryption, rich messaging, spaces, and responsive layouts from mobile to desktop.

## Features

**Messaging**
- Rich text rendering (HTML, Markdown, syntax-highlighted code blocks)
- Message reactions, replies, editing, and deletion
- File and image uploads with progress tracking
- Link previews via OpenGraph
- @mention autocomplete with styled pills
- Typing indicators and read receipts
- Pinned messages
- In-room message search

**End-to-End Encryption**
- Cross-signing and device verification (SAS emoji)
- Key backup setup with recovery key
- Auto-unlock from secure storage on startup
- Backup status indicators and management

**Spaces & Rooms**
- Discord/Slack-style vertical space rail
- Create, edit, and manage spaces
- Room creation, DM creation, and invite flows
- Room details panel with member list and shared media
- Room admin controls

**Adaptive Layouts**

| Width | Layout |
| --- | --- |
| < 720 px | Space rail + room list; chat pushes full-screen |
| 720 – 1100 px | Space rail + room list + content pane (2-column) |
| &ge; 1100 px | Space rail + resizable room list + chat pane (3-column) |

**Other**
- Material You dynamic color theming with light/dark modes
- Theme and layout density picker
- SSO and reCAPTCHA support
- Local and desktop push notifications
- Device management

## Getting Started

### Prerequisites

- Flutter 3.16+ (stable)
- Dart 3.1+

### Setup

```bash
git clone https://github.com/<your-org>/lattice.git
cd lattice
flutter pub get
flutter run              # default device
flutter run -d linux     # Linux desktop
flutter run -d chrome    # Web
```

The app connects to any Matrix homeserver. Enter your homeserver URL, username, and password on the login screen (defaults to `matrix.org`).

### Building for Release

```bash
flutter build linux --release
flutter build windows --release
```

### Web Deployment (Docker)

Build and run the containerized web app locally:

```bash
docker build -t lattice-web .
docker run -p 8080:80 lattice-web
```

Then open `http://localhost:8080`.

Pull the latest release image from GHCR:

```bash
docker pull ghcr.io/quantumheart/lattice:latest
docker run -p 8080:80 ghcr.io/quantumheart/lattice:latest
```

## Architecture

Feature-based organization under `lib/`:

```
lib/
├── main.dart
├── core/
│   ├── extensions/       # Responsive device helpers
│   ├── models/           # Space tree, upload state
│   ├── routing/          # GoRouter configuration
│   ├── services/         # MatrixService + mixins (auth, sync, selection, UIA)
│   ├── theme/            # Material You light/dark themes
│   └── utils/            # Emoji, colors, time formatting, syntax highlighting
├── features/
│   ├── auth/             # Login, registration, SSO, reCAPTCHA
│   ├── chat/             # Message timeline, compose bar, reactions, search
│   ├── e2ee/             # Bootstrap, device verification, key backup
│   ├── home/             # Adaptive shell layout, inbox
│   ├── notifications/    # Push and local notification handling
│   ├── rooms/            # Room list, details, creation, invites, admin
│   ├── settings/         # Preferences, devices, themes, notifications
│   └── spaces/           # Space rail, creation, management
└── shared/widgets/       # Avatars, image viewer, section headers, speed dial
```

**State management:** A single `MatrixService` (ChangeNotifier) provided at the root via Provider. It wraps the Matrix SDK client and manages login, sync, room/space selection, E2EE bootstrap, and UIA flows through composable mixins.

See [`docs/e2ee-flow.md`](docs/e2ee-flow.md) for E2EE state machine diagrams.

## Development

```bash
flutter analyze                                          # Lint
dart run build_runner build --delete-conflicting-outputs  # Generate mocks
flutter test                                             # Run all tests
flutter test test/services/matrix_service_test.dart      # Single test file
```

Mock generation must run before `flutter test` whenever `@GenerateMocks` annotations change.

### Commit Convention

```
feat:     new feature
fix:      bug fix
refactor: code restructuring
style:    formatting only
docs:     documentation
test:     tests
chore:    maintenance
```

## Key Dependencies

| Package | Purpose |
| --- | --- |
| `matrix` | Matrix protocol SDK |
| `flutter_vodozemac` / `vodozemac` | E2EE cryptography (Rust bindings) |
| `provider` | State management |
| `go_router` | Declarative routing |
| `dynamic_color` | Material You palette extraction |
| `cached_network_image` | Image caching |
| `flutter_secure_storage` | Encrypted credential storage |
| `sqflite` | Local database |
| `flutter_local_notifications` | Push notifications |
| `highlight` | Code syntax highlighting |

## CI/CD

GitHub Actions runs on push/PR to `master`:
1. **Analyze** — `flutter analyze`
2. **Test** — mock generation + `flutter test`
3. **Build** — Linux release build

Tagged releases (`v*`) build Linux (tar.gz) and Windows (Inno Setup installer) artifacts and publish a GitHub Release. A separate workflow builds and pushes a web Docker image to `ghcr.io`.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

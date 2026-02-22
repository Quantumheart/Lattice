# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Lattice is a Flutter Matrix chat client targeting Linux desktop. It uses the `matrix` Dart SDK for the Matrix protocol, Provider (ChangeNotifier) for state management, and Material You dynamic color theming. The project currently builds for Linux only (no Android, iOS, or web targets).

## Common Commands

```bash
flutter pub get                                          # Install dependencies
flutter analyze                                          # Lint (uses flutter_lints + custom rules)
dart run build_runner build --delete-conflicting-outputs  # Generate mocks (required before tests)
flutter test                                             # Run all tests
flutter test test/services/matrix_service_test.dart      # Run a single test file
flutter run -d linux                                     # Run on Linux
flutter build linux --release                            # Release build
```

Mock generation (`build_runner`) must run before `flutter test` whenever `@GenerateMocks` annotations change.

**Linux build dependencies:** `ninja-build`, `libgtk-3-dev`, `libsecret-1-dev`

## Architecture

### State management

Single `MatrixService` (ChangeNotifier) provided at the root via Provider. It wraps the Matrix SDK `Client` and is composed of five mixins:

- `AuthMixin` — login, registration, logout, server capability probing
- `ChatBackupMixin` — E2EE backup status, recovery-key storage, auto-unlock
- `UiaMixin` — user-interactive auth, cached password with 5-minute TTL
- `SyncMixin` — client sync lifecycle
- `SelectionMixin` — room/space selection state

**Multi-account support:** `ClientManager` sits above `MatrixService` and manages multiple accounts. Each service gets a unique `clientName` (e.g., `default`, `account_1`). Account list is persisted to `SharedPreferences`.

**Preferences:** `PreferencesService` manages user preferences (theme mode, message density, room filter, panel width) via `SharedPreferences`.

### Responsive layouts

Three breakpoints in `HomeShell`:
- Mobile (<720px) — bottom nav bar + stack navigation
- Tablet (720–1100px) — space rail + room list
- Desktop (>=1100px) — space rail + room list + chat (3-column)

The space rail is Discord/Slack-style vertical icons. The room list panel is resizable (240–500px) on desktop.

### E2EE architecture

Separated into three layers:
- `BootstrapController` (ChangeNotifier) — state machine for key backup/cross-signing setup
- `BootstrapDialog` — modal orchestration
- `BootstrapViews` — stateless UI components

Auto-unlock recovers keys from `FlutterSecureStorage` on startup via `ChatBackupMixin.tryAutoUnlockBackup()`. UIA uses cached password with 5-minute TTL.

See `docs/e2ee-flow.md` for detailed state machine diagrams.

### Testing

Mockito with `@GenerateNiceMocks` and generated mocks (`*.mocks.dart`). Tests cover MatrixService state, auth flows, bootstrap controller transitions, dialog flows, key verification, client manager, session backup, and device extensions.

## File Structure

```
lib/
  main.dart                  # Provider setup, dynamic color theming
  services/
    matrix_service.dart      # Core service (ChangeNotifier + 5 mixins)
    client_manager.dart      # Multi-account management
    preferences_service.dart # User preferences
    session_backup.dart      # Session backup/restore
    recaptcha_server.dart    # Recaptcha verification server
    sso_callback_server.dart # SSO callback handler
    mixins/                  # AuthMixin, ChatBackupMixin, UiaMixin, SyncMixin, SelectionMixin
  screens/                   # login, registration, home_shell, chat, settings, devices
  widgets/                   # bootstrap_*, key_verification_dialog, login/registration controllers,
                             # space_rail, room_list, room_avatar, message_bubble, device_list_item
  theme/
    lattice_theme.dart       # Material You light + dark themes
  extensions/
    device_extension.dart    # Device-related extension methods
test/                        # Mirrors lib/ structure, with *.mocks.dart generated files
docs/
  e2ee-flow.md               # State machine diagrams for E2EE flows
```

## CI/CD

GitHub Actions (`.github/workflows/`):
- **ci.yml** — runs on push/PR to master: `flutter analyze` -> `build_runner` + `flutter test` -> `flutter build linux --release`
- **release.yml** — runs on version tags (`v*`): full test suite, builds Linux release, publishes tarball (`lattice-linux-x64.tar.gz`) via GitHub Releases

## Conventions

- **Commits:** Semantic format — `feat:`, `fix:`, `refactor:`, `style:`, `docs:`, `test:`, `chore:`
- **Logging:** `debugPrint('[Lattice] ...')` prefix for all log messages
- **Code sections:** Organized with `// ── Section Name ──────` markers
- **Linting:** `avoid_print: false` is intentional (uses `debugPrint` instead of `print`)

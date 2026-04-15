# CLAUDE.md

## What is Kohera?

Kohera is a Flutter Matrix chat client. It uses the `matrix` Dart SDK for the Matrix protocol, Provider (ChangeNotifier) for state management, GoRouter for navigation, and Material You dynamic color theming. It supports E2EE, voice/video calling (LiveKit), multi-account, and runs on Linux, macOS, and web.

## How to work with this project

```bash
flutter pub get                                          # Install dependencies
flutter analyze                                          # Lint
dart run build_runner build --delete-conflicting-outputs  # Generate mocks (required before tests)
flutter test                                             # Run all tests
flutter test test/path/to_test.dart                      # Run a single test file
flutter run -d linux                                     # Run on Linux
```

Mock generation (`build_runner`) must run before `flutter test` whenever `@GenerateNiceMocks` annotations change.

## Architecture overview

Feature-based organization under `lib/`: `core/` (services, routing, theme, utils), `features/` (auth, calling, chat, e2ee, home, notifications, rooms, settings, spaces), `shared/widgets/`.

State is managed via multiple ChangeNotifiers provided at the root. `MatrixService` wraps the Matrix SDK client. Extracted sub-services live in `core/services/sub_services/` (AuthService, SyncService, SelectionService, ChatBackupService, UiaService). Other top-level providers include ClientManager, CallService, PreferencesService, and InboxController.

See `agent_docs/architecture.md` for detailed architecture, routing, responsive layout, and E2EE docs. See `docs/e2ee-flow.md` for E2EE state machine diagrams.

## Conventions

- **Commits:** `feat:`, `fix:`, `refactor:`, `style:`, `docs:`, `test:`, `chore:`
- **Logging:** `debugPrint('[Kohera] ...')` prefix for all log messages
- **No comments** -- code should be self-descriptive. Section markers (`// ── Section Name ──────`) are the exception.

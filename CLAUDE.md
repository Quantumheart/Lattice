# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Lattice is a Flutter Matrix chat client built with Dart 3.1+ and Flutter 3.16+. It uses the `matrix` Dart SDK for the Matrix protocol, Provider (ChangeNotifier) for state management, and Material You dynamic color theming.

## Common Commands

```bash
flutter pub get                                          # Install dependencies
flutter analyze                                          # Lint (uses flutter_lints + custom rules)
dart run build_runner build --delete-conflicting-outputs  # Generate mocks (required before tests)
flutter test                                             # Run all tests
flutter test test/services/matrix_service_test.dart      # Run a single test file
flutter run                                              # Run on default device
flutter run -d linux                                     # Run on Linux
flutter build linux --release                            # Release build
```

Mock generation (`build_runner`) must run before `flutter test` whenever `@GenerateMocks` annotations change.

## Architecture

**State management:** Single `MatrixService` (ChangeNotifier) provided at the root via Provider. It wraps the Matrix SDK client and manages login, sync, room/space selection, E2EE bootstrap, and UIA flows.

**Responsive layouts:** Three breakpoints in `HomeShell` — mobile (<720px, bottom nav), tablet (720–1100px, rail+list), desktop (≥1100px, rail+list+chat). The space rail is Discord/Slack-style vertical icons.

**E2EE architecture:** Separated into three layers:
- `BootstrapController` (ChangeNotifier) — state machine for key backup/cross-signing setup
- `BootstrapDialog` — modal orchestration
- `BootstrapViews` — stateless UI components
- Auto-unlock recovers keys from `FlutterSecureStorage` on startup
- UIA uses cached password with 5-minute TTL

See `docs/e2ee-flow.md` for detailed state machine diagrams.

**Testing:** Mockito with generated mocks (`*.mocks.dart`). Tests cover MatrixService state, BootstrapController transitions, dialog flows, and key verification.

## Conventions

- **Commits:** Semantic format — `feat:`, `fix:`, `refactor:`, `style:`, `docs:`, `test:`, `chore:`
- **Logging:** `debugPrint('[Lattice] ...')` prefix for all log messages
- **Code sections:** Organized with `// ── Section Name ──────` markers
- **Linting:** `avoid_print: false` is intentional (uses `debugPrint` instead of `print`)

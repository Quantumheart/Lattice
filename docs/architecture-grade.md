# Architecture Grade: A- (91/100)

## Executive Summary

Lattice is a well-architected Flutter Matrix client with ~13,500 lines of source
code across 87 files. It demonstrates mature engineering practices: clean
separation of concerns, comprehensive testing (14,000 lines across 50 test
files — a 1.04:1 test-to-source ratio), thoughtful E2EE layering, and polished
responsive layouts.

---

## Category Scores

| Category | Grade | Score | Highlights |
|----------|-------|-------|------------|
| Project Organization | A | 94 | Clear layer separation, feature grouping, mixin decomposition |
| State Management | A- | 90 | Single-source-of-truth MatrixService, mixin composition, DI |
| UI Architecture | A | 93 | Three responsive breakpoints, adaptive nav, keyboard shortcuts |
| E2EE Architecture | A+ | 97 | Exemplary 3-layer separation, auto-unlock, documented state machine |
| Testing | A | 92 | 1.04:1 test-to-source ratio, covers all major subsystems |
| Code Quality | A- | 89 | Consistent conventions, secure storage, structured logging |
| Dependency Management | A- | 88 | 22 lean runtime deps, SDK properly abstracted |

---

## 1. Project Organization (A — 94/100)

### Strengths

- **Clear layer separation**: `screens/`, `services/`, `widgets/`, `models/`,
  `utils/`, `theme/` each have well-defined responsibilities.
- **Feature grouping**: `widgets/chat/` groups 26 chat-specific components
  together.
- **Mixin decomposition**: `services/mixins/` breaks MatrixService into 5
  focused concerns (auth, sync, selection, UIA, chat backup).
- **Flat where appropriate**: No over-nested hierarchy; any file is easy to
  locate.

### Deductions

- `widgets/` mixes controllers (`bootstrap_controller.dart`,
  `login_controller.dart`) with pure UI components. A dedicated `controllers/`
  directory would improve discoverability.

---

## 2. State Management (A- — 90/100)

### Strengths

- **Single source of truth**: One `MatrixService` ChangeNotifier for all Matrix
  state, provided at the root via Provider.
- **Mixin composition**: `MatrixService with SelectionMixin, ChatBackupMixin,
  UiaMixin, SyncMixin, AuthMixin` keeps each concern in its own file while
  maintaining a single reactive notification point.
- **Dependency injection**: Constructor injection of `Client`, `Storage`,
  `ClientFactory` enables clean testing.
- **Local state isolation**: `ValueNotifier` for reply/edit/upload in
  `ChatScreen` avoids unnecessary global rebuilds.
- **Multi-account**: `ClientManager` manages multiple `MatrixService` instances
  with account switching.

### Deductions

- **Cross-mixin coupling**: `AuthMixin` calls `listenForUia()`,
  `startSync()`, `resetSelection()`, `resetChatBackupState()` — an implicit
  dependency graph not enforced by the type system.
- **Coarse notification granularity**: Any change in any mixin triggers
  `notifyListeners()`, rebuilding all consumers. `context.select()` would help
  in hot paths.

---

## 3. UI Architecture (A — 93/100)

### Strengths

- **Three responsive breakpoints** in `HomeShell`:
  - Mobile (<720 px): bottom nav + stack navigation
  - Tablet (720–1100 px): space rail + room list
  - Desktop (>=1100 px): space rail + room list + chat + details panel
- **Discord-style SpaceRail**: Vertical icon bar with drag-to-reorder, multi-
  select, unread badges, and account menu.
- **Keyboard shortcuts**: Ctrl+0-9 for space selection on desktop.
- **Draggable panels**: Room list width is resizable and persisted.
- **Stateless widgets**: Most components are pure presentation (`_RailIcon`,
  `_RoomTile`, `_SectionHeader`).

### Deductions

- **No routing library**: No deep linking, URL-based navigation, or browser
  back/forward support. Acceptable for desktop/mobile but limits web
  deployment.

---

## 4. E2EE Architecture (A+ — 97/100)

### Strengths

- **Three-layer separation**:
  - `BootstrapController` (ChangeNotifier) — state machine with 10+ states
  - `BootstrapDialog` — modal orchestration, UIA bridging, lifecycle management
  - `BootstrapViews` — completely stateless UI rendering functions
- **Auto-unlock**: Recovery key stored in `FlutterSecureStorage`, headless
  restore on startup via `_tryAutoUnlockBackup()`.
- **UIA with cached password**: 5-minute TTL avoids re-prompting during
  bootstrap.
- **SAS verification**: Full emoji comparison flow with 30-second secret
  propagation timeout.
- **Session backup/restore**: Redundant session persistence with OLM account
  pickling and multi-fallback restore chain.
- **Comprehensive documentation**: 474-line `docs/e2ee-flow.md` with ASCII
  state machine diagrams and source line references.
- **Post-bootstrap hardening**: Key backup cross-signing, secret caching,
  device self-signing, and automatic key re-requests for undecryptable messages.

---

## 5. Testing (A — 92/100)

### Strengths

| Metric | Value |
|--------|-------|
| Test files | 50 `*_test.dart` files |
| Test lines | ~14,000 (excluding generated mocks) |
| Test:Source ratio | **1.04:1** |
| Mock framework | Mockito with `build_runner` code generation |
| CI pipeline | analyze -> test -> build-linux (sequential) |

- Covers all major subsystems: MatrixService state transitions, auth flows,
  BootstrapController state machine, dialog flows, chat components (compose,
  reactions, read receipts, mentions), and utilities.
- 33 `@GenerateNiceMocks` annotations with proper SDK type mocking.
- Integration-style flow tests for bootstrap (10+ multi-step scenarios).

### Deductions

- No integration or end-to-end tests with a real Matrix server.
- Some screens lack dedicated tests (`settings_screen`, `chat_screen`) —
  though their constituent widgets are individually tested.
- `message_bubble.dart` (1,355 lines, the largest file) has no dedicated test.

---

## 6. Code Quality & Conventions (A- — 89/100)

### Strengths

- **Consistent logging**: `debugPrint('[Lattice] ...')` with prefix throughout.
- **Section markers**: `// ── Section Name ──────` for code organization.
- **Semantic commits**: `feat:`, `fix:`, `refactor:`, `style:`, `docs:`,
  `test:`, `chore:`.
- **Lint enforcement**: `flutter_lints` with const constructor preference.
- **Secure storage**: All credentials in `FlutterSecureStorage`, never in
  `SharedPreferences`.
- **Error classification**: `isPermanentAuthFailure()` distinguishes
  recoverable from permanent errors; `friendlyAuthError()` maps exceptions to
  user-facing strings.

### Deductions

- `message_bubble.dart` at 1,355 lines is a candidate for sub-widget
  extraction.
- `room_list.dart` at 925 lines handles filtering, sectioning, search, and
  rendering — data transformation logic could be extracted.
- Generic `catch (e)` blocks are common; custom exception types would improve
  error granularity.

---

## 7. Dependency Management (A- — 88/100)

### Strengths

- **Lean runtime deps**: 22 packages, all well-established.
- **SDK abstraction**: Matrix SDK fully wrapped behind `MatrixService`, never
  leaked to UI layer.
- **Multi-platform**: Proper platform-specific handling (sqflite FFI for
  desktop, native for mobile).
- **Dev deps isolated**: `mockito`, `build_runner`, `fake_async` only in dev.

### Deductions

- Manual dependency injection (no DI framework) — acceptable at this scale but
  `ClientFactory` typedef and constructor injection are doing significant
  manual work.

---

## Architecture Diagram

```
┌───────────────────────────────────────────────────────────┐
│                       main.dart                            │
│  MultiProvider                                             │
│  ├── ClientManager (multi-account)                         │
│  ├── PreferencesService (persistent UI state)              │
│  ├── OpenGraphService (link previews)                      │
│  └── MatrixService.value (active account)                  │
│       with AuthMixin | SyncMixin | SelectionMixin          │
│            UiaMixin  | ChatBackupMixin                     │
├────────────────────────┬──────────────────────────────────┤
│      Screens           │           Widgets                 │
│  ┌──────────────┐      │  ┌────────────────┐              │
│  │ HomeShell     │      │  │ SpaceRail      │              │
│  │ (responsive)  │      │  │ RoomList       │              │
│  │ ChatScreen    │      │  │ chat/* (26)    │              │
│  │ Settings      │      │  │ Bootstrap*     │              │
│  │ Login/Reg     │      │  │ Dialogs        │              │
│  └──────────────┘      │  └────────────────┘              │
├────────────────────────┴──────────────────────────────────┤
│  Services Layer                                            │
│  ┌─────────────┐ ┌──────────────┐ ┌───────────────────┐   │
│  │MatrixService │ │Notification  │ │PreferencesService │   │
│  │ (378 LOC)    │ │Service       │ │                   │   │
│  │ + 5 mixins   │ │ (449 LOC)    │ │                   │   │
│  └──────┬───────┘ └──────────────┘ └───────────────────┘   │
│         │                                                  │
├─────────┼──────────────────────────────────────────────────┤
│  SDK    │  matrix ^6.1.1  │  flutter_secure_storage        │
│         │  vodozemac      │  sqflite  │  shared_prefs      │
└─────────┴──────────────────────────────────────────────────┘
```

---

## Top Improvement Opportunities

| Priority | Issue | Recommendation |
|----------|-------|----------------|
| Medium | `message_bubble.dart` is 1,355 LOC | Extract sub-widgets (reply preview, media content, text formatting) |
| Medium | No routing library | Consider `go_router` for deep linking and web support |
| Low | Controllers mixed with widgets | Move `*_controller.dart` files to `lib/controllers/` |
| Low | Coarse `notifyListeners()` | Add `context.select()` in hot rebuild paths |
| Low | No screen-level tests | Add widget tests for `ChatScreen` and `SettingsScreen` |
| Low | No integration tests | Add `integration_test/` for critical flows |
| Low | Generic catch blocks | Introduce custom exception types (`AuthError`, `SyncError`) |

---

## Conclusion

Lattice demonstrates **professional-grade architecture** for a Flutter project.
The E2EE layering is exemplary, the responsive layout system is well-executed,
testing is thorough, and the codebase follows consistent conventions. The main
weaknesses — a couple of oversized files and the absence of a routing library —
are both addressable without architectural changes. This is a codebase that
would be straightforward to onboard new contributors to and maintain long-term.

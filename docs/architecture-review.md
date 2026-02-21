# Service Architecture Review: Lattice

**Grade: A-**

**Date:** 2026-02-21

---

## Architecture Overview

Lattice is ~3,200 lines of Dart across 32 source files, serving as a Matrix chat client. The architecture follows a clean three-layer structure:

```
Provider (DI) Layer     →  main.dart
Service Layer           →  MatrixService, ClientManager, PreferencesService
Controller Layer        →  LoginController, RegistrationController, BootstrapController
Presentation Layer      →  Screens, Widgets
```

---

## Strengths

### 1. Mixin-based decomposition of MatrixService

The central `MatrixService` is composed from five focused mixins (`lib/services/matrix_service.dart:59-60`):

```dart
MatrixService extends ChangeNotifier
    with SelectionMixin, ChatBackupMixin, UiaMixin, SyncMixin, AuthMixin
```

Each mixin owns a single domain: room/space selection, E2EE backup, user-interactive auth, sync lifecycle, and authentication. This avoids the god-object problem that plagues many Flutter apps that start with a single "AppState" service. The cross-mixin dependency declarations (e.g., `SyncMixin` declaring `Future<void> checkChatBackupStatus()` as an abstract dependency) make the contract between mixins explicit.

### 2. Controller state machines

`LoginController`, `RegistrationController`, and `BootstrapController` all follow the same disciplined pattern: a state enum, private fields with public getters, a `_notify()` guard checking `_isDisposed`, and explicit state transitions. This consistency makes the codebase predictable. The generation-counter pattern in `LoginController` correctly handles stale async results from superseded server checks, which is a subtle bug that many apps get wrong.

### 3. Dependency injection without a framework

Constructor injection is used throughout: `MatrixService` takes optional `Client` and `FlutterSecureStorage`, `ClientManager` takes an optional `MatrixServiceFactory`. This keeps the code testable without bringing in a DI container. The factory typedef pattern for `ClientManager` is well-chosen for enabling mock injection in tests.

### 4. Provider hierarchy is correct

The `main.dart` provider tree nests `MatrixService` under `ClientManager` using `Consumer2` and `.value`, so the active service swaps reactively when accounts switch. This is the right approach for multi-account support. The consistent use of `context.watch<T>()` in build methods and `context.read<T>()` in callbacks throughout the widget layer shows discipline.

### 5. Clean resource lifecycle

All three controllers guard against post-dispose notifications (`_isDisposed` checks). `SsoCallbackServer` and `RecaptchaServer` properly use `Completer` with timeout timers and idempotent `dispose()`. The UIA password has a 5-minute TTL timer, which is a thoughtful security measure.

### 6. Testability

15 test files with generated Mockito mocks covering services, controllers, and UI flows. The architecture makes this easy—every service and controller can be instantiated with mock dependencies.

---

## Issues

### 1. Code duplication in `init()` and `initClient()` (moderate)

`MatrixService.init()` and `initClient()` share ~15 identical lines constructing the `Client`—database setup, `sqfliteFfiInit`, `NativeImplementationsIsolate`, verification methods. If a constructor parameter changes (e.g., timeout, log level), it must be updated in two places. Extract a `_createClient()` helper.

### 2. Controllers live in `lib/widgets/` (minor, organizational)

`LoginController`, `RegistrationController`, and `BootstrapController` are business-logic state machines with no widget code, but they live under `lib/widgets/`. They would be more discoverable under `lib/controllers/` or `lib/services/`. This is purely organizational but matters as the codebase grows.

### 3. Mixin cross-dependencies are implicit contracts (moderate)

Each mixin declares abstract getters and methods it needs from other mixins. These work, but they're duck-typed contracts—there's no compile-time enforcement that `MatrixService` satisfies them all until you actually compose the class. As the mixin count grows, this becomes fragile. An alternative would be an interface that `MatrixService` implements, giving a single source of truth for the contract.

### 4. `SelectionMixin.rooms` recomputes on every access (minor)

The `rooms` getter filters and sorts the full room list on every call. In a build method that calls `matrix.rooms` multiple times, this recomputes redundantly. For a chat app with hundreds of rooms, this could become a performance bottleneck. Consider caching the filtered result and invalidating on sync/selection change.

### 5. No error boundary or retry abstraction (minor)

The auth flows in `AuthMixin` (`login`, `completeSsoLogin`, `completeRegistration`) all follow the same try/catch/log/notifyListeners pattern. There's no shared error-handling wrapper. This isn't a bug, but it's a maintenance cost—every new auth flow will duplicate the same boilerplate.

### 6. Session restore fallback chain is complex (minor)

`MatrixService.init()` has a three-level fallback: primary restore → session backup restore → retry without device ID. The nesting of `_restoreFromBackup()` within the catch block of primary restore, and `_retryInitWithoutDevice()` within a string-contains check (`'$e'.contains('Upload key failed')`), makes this path hard to follow. The string matching is brittle—if the SDK changes the error message, this breaks silently.

### 7. No navigation abstraction (acceptable for now)

Navigation is imperative (`Navigator.push`) with no router. This works fine at the current scale (~6 screens) but will become a liability if deep linking or URL-based navigation is ever needed. Not a current problem, just something to watch.

---

## What's Missing (but may not be needed yet)

- **Repository layer**: Services talk directly to the Matrix SDK and secure storage. At this scale that's appropriate; a repository abstraction would be over-engineering.
- **Event bus / stream architecture**: The app relies entirely on `ChangeNotifier` + `notifyListeners()`. No Bloc, no Riverpod, no event streams. This is fine for the current complexity but would need reconsideration if the app grows significantly.
- **Logging framework**: Uses `debugPrint('[Lattice] ...')` everywhere. Works, but no log levels, no structured output, no crash reporting integration.

---

## Summary

| Category | Grade | Notes |
|---|---|---|
| Separation of concerns | A | Clean service/controller/widget split |
| State management | A | Consistent ChangeNotifier + Provider pattern |
| Dependency injection | A | Constructor injection, factory pattern, fully mockable |
| Code organization | B+ | Mixin decomposition is good; file placement could be cleaner |
| Error handling | B | Consistent patterns but some string matching and duplication |
| Testability | A | 15 test files, generated mocks, controllers fully testable |
| Scalability readiness | B | Suitable for current size; some patterns won't scale without changes |

**Overall: A-**

The architecture is well above average for a Flutter app of this size. The mixin decomposition, state-machine controllers, and constructor injection show deliberate design. The issues identified are maintenance risks and organizational nits rather than architectural flaws. The codebase would benefit most from extracting the duplicated `Client` construction and moving controllers to their own directory.

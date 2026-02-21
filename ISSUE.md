# feat: Separate homeserver input into dedicated screen

## Summary

Separate the homeserver input from the login screen into its own dedicated screen, creating a two-step authentication flow: **homeserver selection** → **credential entry**.

## Current Behavior

The login screen (`lib/screens/login_screen.dart`) currently combines homeserver selection and authentication into a single unified form:

1. Homeserver text field (pre-filled with `matrix.org`)
2. Username and password fields
3. SSO provider buttons

All of these are rendered in one vertical stack. The homeserver field uses an 800ms debounce to probe server capabilities via `MatrixService.getServerAuthCapabilities()`, and the form dynamically shows/hides password or SSO options based on what the server supports.

## Proposed Change

Split the flow into two distinct screens:

### Screen 1: Homeserver Selection
- Prominent homeserver URL input field
- "Continue" / "Next" button to proceed
- Validates the server and fetches `ServerAuthCapabilities` before advancing
- Shows loading state during server probe and clear error messages on failure
- Could optionally show a list of popular/recent homeservers

### Screen 2: Login / Authentication
- Displays the selected homeserver (read-only or as a small chip/link to go back)
- Shows only the relevant auth methods (password fields, SSO buttons) based on capabilities fetched in step 1
- Back navigation returns to homeserver selection

## Motivation

- **Clearer UX flow**: Users unfamiliar with Matrix may not understand what a homeserver is. A dedicated screen can provide better context and explanation.
- **Reduced visual clutter**: The login screen currently shows the homeserver field alongside credentials, which can be overwhelming.
- **Better error handling**: Server connection errors are isolated to their own step, so users resolve server issues before ever seeing login fields.
- **Follows common patterns**: Many Matrix clients (Element, FluffyChat) use a similar two-step approach.
- **Extensible**: The homeserver screen can later support server discovery, server lists, or QR-code-based server selection.

## Implementation Notes

### Architecture (existing code supports this well)
- `MatrixService.getServerAuthCapabilities()` in `lib/services/mixins/auth_mixin.dart` already works independently of login — it probes the server, checks `.well-known`, fetches login flows, and returns a `ServerAuthCapabilities` object.
- `LoginController` in `lib/widgets/login_controller.dart` manages a `LoginState` enum (`checkingServer` → `formReady` → `loggingIn` → `done`). This can be extended or split.
- The `RegistrationScreen` already follows a similar modal-push navigation pattern and can serve as a reference.

### Suggested approach
1. Create `HomeserverScreen` widget + optional `HomeserverController` (ChangeNotifier)
2. On successful server probe, navigate to `LoginScreen` passing the homeserver URL and `ServerAuthCapabilities`
3. Update `LoginController` to accept homeserver/capabilities as constructor parameters instead of probing on init
4. Update root routing in `main.dart` (currently `isLoggedIn ? HomeShell() : LoginScreen()`) to start at `HomeserverScreen`
5. Update existing tests to cover the new two-screen flow

### Files likely to change
- `lib/screens/login_screen.dart` — Remove homeserver field, accept capabilities as parameter
- `lib/widgets/login_controller.dart` — Remove server-probing logic, accept homeserver as input
- `lib/main.dart` — Update root routing to point to `HomeserverScreen`
- **New:** `lib/screens/homeserver_screen.dart`
- **New (optional):** `lib/widgets/homeserver_controller.dart`
- `test/screens/login_screen_test.dart` — Update for new flow
- `test/widgets/login_controller_test.dart` — Update for new constructor

# E2E Test Paths for Lattice

This document identifies the critical user-facing code paths that should be covered by end-to-end (integration) tests, ordered by priority.

## Current State

- **No `integration_test/` directory exists** — there are zero E2E tests today.
- Existing unit/widget tests cover individual controllers, services, and widgets in isolation but do not exercise full user flows through the real router, provider tree, and Matrix SDK.

---

## Priority 1 — Authentication (Gate to Everything)

Every user session starts here. A broken auth flow means zero usability.

### 1a. Password Login Flow

**Path:** `HomeserverScreen` → enter homeserver → `LoginScreen` → enter credentials → `HomeShell`

| Step | Key Code |
|------|----------|
| Homeserver resolution | `homeserver_controller.dart` → `AuthMixin.getServerAuthCapabilities()` |
| Login submission | `login_controller.dart` → `AuthMixin.login()` |
| Post-login sync | `AuthMixin._postLoginSync()` → credential persistence, sync start |
| Router redirect | `app_router.dart:27-33` — logged-in redirect to `/` |

**What to verify:**
- Homeserver field validates and resolves (including `.well-known`)
- Bad credentials show error, good credentials land on HomeShell
- Session persisted to secure storage (survives restart)

### 1b. SSO Login Flow

**Path:** `HomeserverScreen` → SSO provider button → browser redirect → `AuthMixin.completeSsoLogin()` → `HomeShell`

| Step | Key Code |
|------|----------|
| SSO callback server | `sso_callback_server.dart` |
| SSO login completion | `AuthMixin.completeSsoLogin()` |

**What to verify:**
- SSO identity providers render when server supports them
- Login token exchange works end-to-end

### 1c. Registration Flow

**Path:** `RegistrationScreen` → complete stages (reCAPTCHA, terms, etc.) → `AuthMixin.completeRegistration()` → `HomeShell`

| Step | Key Code |
|------|----------|
| Stage progression | `registration_controller.dart` → `registration_views.dart` |
| Registration completion | `AuthMixin.completeRegistration()` |

### 1d. Logout

**Path:** `SettingsScreen` → logout button → `AuthMixin.logout()` → `HomeserverScreen`

**What to verify:**
- Session keys cleared from secure storage
- Router redirects to `/login`
- Soft logout / server-side logout handled (`AuthMixin.handleSoftLogout()`, `listenForLoginState()`)

---

## Priority 2 — Messaging (Core Value Proposition)

### 2a. Send & Receive Text Messages

**Path:** `HomeShell` → select room from `RoomList` → `ChatScreen` → type in `ComposeBar` → send → message appears in timeline

| Step | Key Code |
|------|----------|
| Room selection | `SelectionMixin.selectRoom()` → router navigates to `/rooms/:roomId` |
| Timeline loading | `ChatScreen._initTimeline()` |
| Message sending | `ChatScreen._handleSend()` → `Room.sendTextEvent()` |
| Timeline rendering | `MessageBubble`, `html_message_text.dart`, `linkable_text.dart` |

**What to verify:**
- Message appears locally immediately (optimistic/local echo)
- Message persists after sync
- Incoming messages from other users render in real-time
- Read markers / receipts update (`read_receipts.dart`)

### 2b. Reply & Edit

**Path:** Long-press/swipe message → reply/edit action → compose bar shows preview → send

| Step | Key Code |
|------|----------|
| Reply trigger | `swipeable_message.dart`, `message_action_sheet.dart` |
| Reply preview | `reply_preview_banner.dart`, `inline_reply_preview.dart` |
| Edit preview | `edit_preview_banner.dart` |
| Send with relation | `ChatScreen._handleSend()` with `replyNotifier`/`editNotifier` |

### 2c. Reactions

**Path:** Long-press message → pick emoji → reaction chip appears

| Step | Key Code |
|------|----------|
| Reaction sending | `message_action_sheet.dart` → `Room.sendReaction()` |
| Reaction display | `reaction_chips.dart` |

### 2d. File & Media Sending

**Path:** Attach button → pick file/image → preview → send → upload progress → media bubble

| Step | Key Code |
|------|----------|
| Attachment flow | `file_send_handler.dart`, `paste_image_handler.dart` |
| Upload tracking | `upload_progress_banner.dart` |
| Media rendering | `image_bubble.dart`, `video_bubble.dart`, `audio_bubble.dart`, `file_bubble.dart` |

---

## Priority 3 — E2EE Bootstrap & Key Verification

Encryption failures silently break messaging. These flows are complex state machines that are hard to unit-test in isolation.

### 3a. First-Device Bootstrap

**Path:** Login on new device → `BootstrapDialog` opens → generate recovery key → copy/save → cross-signing setup complete

| Step | Key Code |
|------|----------|
| Bootstrap state machine | `bootstrap_controller.dart` (BootstrapState transitions) |
| Dialog orchestration | `bootstrap_dialog.dart` |
| Recovery key save | `BootstrapController.confirmNewKey()` → `FlutterSecureStorage` |

**What to verify:**
- State machine progresses: `loading` → `askNewKey` → `awaitKeyAck` → `done`
- Recovery key auto-saved to device when `saveToDevice` is checked
- Cross-signing keys created and uploaded

### 3b. Existing-Key Unlock

**Path:** Login on second device → `BootstrapDialog` → enter recovery key → keys unlocked

**What to verify:**
- `askExistingKey` state renders passphrase input
- Correct key unlocks SSSS (`OpenSSSS`)
- Incorrect key shows error, allows retry

### 3c. Device Verification

**Path:** Emoji verification request → `KeyVerificationDialog` → compare emojis → confirm → verified

| Step | Key Code |
|------|----------|
| Verification flow | `key_verification_dialog.dart` |

---

## Priority 4 — Room & Space Management

### 4a. Create Room

**Path:** FAB / "+" button → `NewRoomDialog` → fill name → create → room appears in list → navigated to

| Step | Key Code |
|------|----------|
| Room creation | `new_room_dialog.dart` → `Client.createRoom()` |

### 4b. Create DM

**Path:** "+" button → `NewDmDialog` → search user → create → DM room opens

| Step | Key Code |
|------|----------|
| DM creation | `new_dm_dialog.dart` |

### 4c. Join / Leave / Invite

| Flow | Key Code |
|------|----------|
| Accept invite | `invite_tile.dart` → `Room.join()` |
| Invite user | `invite_user_dialog.dart` |
| Leave room | `room_context_menu.dart` → `Room.leave()` |

### 4d. Space Operations

| Flow | Key Code |
|------|----------|
| Create space | `space_action_dialog.dart` |
| Create subspace | `create_subspace_dialog.dart` |
| Add rooms to space | `add_existing_rooms_dialog.dart`, `add_room_to_space_dialog.dart` |
| Space navigation | `space_rail.dart` → `SelectionMixin.selectSpace()` |
| Space reparenting (drag) | `space_reparent_controller.dart` |

---

## Priority 5 — Navigation & Layout

### 5a. Responsive Layout Transitions

**Path:** Resize window across breakpoints → layout changes correctly

| Breakpoint | Layout | Key Code |
|------------|--------|----------|
| < 720px | Mobile (bottom nav, full-screen chat push) | `home_shell.dart` |
| 720–1100px | Tablet (rail + room list) | `home_shell.dart` |
| ≥ 1100px | Desktop (rail + room list + chat side-by-side) | `home_shell.dart` |

**What to verify:**
- Room list → chat transition works on narrow screens (push navigation)
- Three-column layout renders on wide screens
- Details panel toggle works on desktop (`_showRoomDetails`)
- Room list panel resizable via drag divider

### 5b. Deep Linking

**Path:** Navigate directly to `/rooms/:roomId` → correct room loads

| Step | Key Code |
|------|----------|
| Route matching | `app_router.dart:79-85` |
| Room selection sync | `HomeShell._syncRoomSelection()` |

---

## Priority 6 — Notifications & Inbox

### 6a. Inbox / Notification List

**Path:** Navigate to `/inbox` → see unread rooms / mentions

| Step | Key Code |
|------|----------|
| Inbox rendering | `inbox_screen.dart`, `inbox_controller.dart` |
| Notification filtering | `notification_filter_test.dart` (logic), `notification_service.dart` |

### 6b. Notification Settings

**Path:** `SettingsScreen` → notification settings → change push rules

| Step | Key Code |
|------|----------|
| Settings UI | `notification_settings_screen.dart` |
| Per-space overrides | `notification_radio_group.dart` |

---

## Priority 7 — Settings & Device Management

### 7a. Device Management

**Path:** Settings → Devices → see sessions → rename/remove device

| Step | Key Code |
|------|----------|
| Device list | `devices_screen.dart`, `device_list_item.dart` |
| UIA for device removal | `UiaMixin` |

### 7b. Room Admin Settings

**Path:** Room details panel → admin section → change permissions/history visibility

| Step | Key Code |
|------|----------|
| Admin settings | `admin_settings_section.dart` |
| Room details | `room_details_panel.dart`, `room_members_section.dart`, `shared_media_section.dart` |

---

## Recommended Test Infrastructure

1. **Use `integration_test/` with `IntegrationTestWidgetsFlutterBinding`** — Flutter's standard integration test framework.
2. **Mock at the Matrix SDK boundary** — Use a fake/mock `Client` to avoid needing a real homeserver, but exercise everything above: router, providers, widgets, controllers.
3. **Consider [Synapse](https://github.com/element-hq/synapse) in Docker** for true E2E tests against a real server (slower but highest confidence for auth and E2EE flows).
4. **Group tests by priority** — Start with Priority 1 (auth) and Priority 2 (messaging) as they cover the core user journey.

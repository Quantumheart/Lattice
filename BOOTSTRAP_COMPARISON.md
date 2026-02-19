# E2EE Bootstrap: FluffyChat vs Lattice — Comparison & Bug Fix Plan

## Overview

Both apps use the Matrix Dart SDK's `Bootstrap` state machine (`client.encryption!.bootstrap(onUpdate: callback)`). FluffyChat's implementation is mature and battle-tested; Lattice's was built recently and has several behavioral differences that manifest as bugs.

---

## Architecture Comparison

| Aspect | FluffyChat | Lattice |
|--------|-----------|---------|
| **Structure** | Single `StatefulWidget` (~580 lines) with all logic inline | MVC split: `BootstrapController` (ChangeNotifier) + `bootstrap_views.dart` + thin `BootstrapDialog` shell |
| **UI paradigm** | Full-screen `LoginScaffold` page (route `/backup`) | Modal `AlertDialog` via `showDialog` |
| **State machine** | `setState(() {})` in `onUpdate` — rebuilds entire widget on every bootstrap state change | `ChangeNotifier.notifyListeners()` — dialog listens and calls `setState` |
| **Deferred advances** | `WidgetsBinding.instance.addPostFrameCallback` called directly in `build()` | Controller sets `deferredAdvance` callback; dialog consumes it in listener and wraps with `addPostFrameCallback` |

---

## Key Behavioral Differences (Bugs in Lattice)

### Bug 1: `askUseExistingSsss` is NOT auto-advanced

**FluffyChat:** Auto-advances this state — `bootstrap.useExistingSsss(!_wipe!)` — the user never sees this prompt. When `_wipe` is false (normal flow), it uses the existing SSSS. When true, it creates new.

**Lattice:** Shows an interactive prompt ("Use existing backup" / "Create new") and waits for user input. This is confusing because users don't understand what SSSS is and shouldn't need to make this choice.

**Impact:** Unnecessary user friction; users may accidentally choose "Create new" and lose their existing backup.

**Fix:** Auto-advance `askUseExistingSsss` like FluffyChat does — call `bootstrap.useExistingSsss(!_wipeExisting)` automatically.

---

### Bug 2: `askUnlockSsss` shows an unlock prompt instead of auto-advancing

**FluffyChat:** Auto-advances with `bootstrap.unlockedSsss()` — silently skips old SSSS key migration. The user is never asked to enter their old recovery key.

**Lattice:** Shows a text field asking the user to enter their recovery key to "migrate old secrets", with a Skip button. Most users won't have their old key and will be confused.

**Impact:** Confusing UX; users see two different recovery key prompts (one for old SSSS, one for current). The "Skip" button is the only practical option for most users.

**Fix:** Auto-advance `askUnlockSsss` by calling `bootstrap.unlockedSsss()` immediately, matching FluffyChat's behavior.

---

### Bug 3: `askNewSsss` — recovery key display gate differs

**FluffyChat:** Calls `bootstrap.newSsss()` in `addPostFrameCallback` (auto-advances), then intercepts the recovery key display at the *top* of `build()` — checks `bootstrap.newSsssKey?.recoveryKey != null && _recoveryKeyStored == false` *before* the state switch. The "Next" button requires either copying the key or choosing secure storage before enabling.

**Lattice:** Uses `_awaitingKeyAck` flag to gate the state machine. Calls `bootstrap.newSsss()` asynchronously in `_generateNewSsssKey()`. The "Next" button is always enabled once key generation completes — the user can skip without copying or saving.

**Impact:** Users can proceed without actually saving their recovery key, potentially losing access to encrypted messages forever.

**Fix:** Require the user to either copy the key or check "Save to device" before enabling "Next", matching FluffyChat's approach.

---

### Bug 4: `onUiaRequest` stream has no UI consumer

**FluffyChat:** Has a full UIA handling system — password prompt dialog, email verification, web fallback — wired up in the `Matrix` widget.

**Lattice:** `MatrixService._handleUiaRequest()` auto-completes password UIA *only if* `_cachedPassword` is set (i.e., the user just logged in). On session restore (app restart), the password is not cached. UIA requests are forwarded to `_uiaController.stream` — but **no widget subscribes to this stream**. The bootstrap will silently hang when cross-signing keys need to be uploaded.

**Impact:** Bootstrap hangs on restored sessions. Users must log out and log back in for bootstrap to work.

**Fix:** Either (a) persist the password in secure storage (less ideal for security), or (b) add a UIA password prompt dialog that listens to `onUiaRequest` and calls `completeUiaWithPassword()`.

---

### Bug 5: No self-sign after unlocking existing SSSS

**FluffyChat:** After successfully unlocking SSSS with a recovery key (`openExistingSsss` path), immediately calls `encryption.crossSigning.selfSign(recoveryKey: key)` to self-sign the device.

**Lattice:** Only calls `selfSign` in `onDone()` (post-bootstrap), and uses `openSsss: ssssKey` instead of `recoveryKey: key`. The self-sign does NOT happen immediately after unlock — it happens after the user clicks "Done". If the bootstrap hits an error between unlock and done, the self-sign never happens.

**Impact:** The device may not be cross-signed after unlocking an existing backup, leaving it in an "unverified" state.

**Fix:** Add self-sign immediately after `bootstrap.openExistingSsss()` succeeds in `unlockExistingSsss()`.

---

### Bug 6: No post-bootstrap key re-request for undecryptable messages

**FluffyChat:** After successful bootstrap, iterates all rooms and calls `keyManager.maybeAutoRequest()` for any `BadEncrypted` last event that has `can_request_session = true`. This automatically recovers previously undecryptable messages.

**Lattice:** Does nothing after bootstrap to re-request missing keys.

**Impact:** After setting up backup, old encrypted messages that failed to decrypt remain broken until the user manually triggers a key request or restarts the app.

**Fix:** Add a `_decryptLastEvents()` call in `onDone()` after the caching/self-sign step.

---

### Bug 7: Broader account data removal than intended

**FluffyChat:** No account data removal workaround — relies on SDK to handle stale data.

**Lattice:** `bootstrap_controller.dart:135-138` removes *any* account data event where `content['encrypted']` exists but isn't a `Map`. The original fix (commit `11cb181`) only removed 4 specific SSSS-related types. The refactored version broadened this to a pattern match that could affect unrelated account data.

**Impact:** Could silently delete non-SSSS account data that happens to have a malformed `encrypted` field.

**Fix:** Restrict the removal to the 4 known SSSS event types:
- `m.cross_signing.master`
- `m.cross_signing.self_signing`
- `m.cross_signing.user_signing`
- `m.megolm_backup.v1`

---

### Bug 8: No cancel confirmation dialog

**FluffyChat:** `_cancelAction()` shows a confirmation dialog warning that messages may be lost if the user skips backup, using `showOkCancelAlertDialog` with a destructive "Skip" button.

**Lattice:** All "Cancel" buttons immediately call `Navigator.pop(context)` with no confirmation. Users can accidentally dismiss the bootstrap process.

**Impact:** Users may accidentally skip backup setup, leaving their encrypted messages unrecoverable.

**Fix:** Add a cancel confirmation dialog before closing the bootstrap.

---

### Bug 9: No error retry mechanism

**FluffyChat:** Error state shows a "Close" button (same as Lattice). Users must re-open from settings. Not ideal but functional.

**Lattice:** Same — error state only shows "Close". No retry.

**Impact:** Both apps lack retry. This is minor but worth adding.

**Fix:** Add a "Retry" button to the error state that calls `restartWithWipe(false)` (restart without wiping).

---

### Bug 10: Verification flow waits for secrets differently

**FluffyChat:** After successful verification, checks `isCached()` for both key manager and cross-signing. If not cached, waits for `ssss.onSecretStored.stream.first`. Then calls `_goBackAction(true)` to close the entire bootstrap.

**Lattice:** Listens for `onSecretStored` and then tries to call `bootstrap.openExistingSsss()` — but doesn't check if secrets are actually cached first. Also doesn't close the bootstrap after verification succeeds; the user stays in the dialog.

**Impact:** After successful device verification, the user may see an error or be stuck in an intermediate state.

**Fix:** Match FluffyChat's pattern — check `isCached()` first, wait for secrets if needed, then finalize and close.

---

## Minor Differences (Not Bugs)

| Aspect | FluffyChat | Lattice | Notes |
|--------|-----------|---------|-------|
| Sync status display | Shows `onSyncStatus` stream with progress bar during initial load | Shows generic "Preparing..." spinner | Nice-to-have |
| Secure storage label | Platform-specific ("Android Keystore" / "Apple Keychain" / "Secure storage") | Generic "Save to device" | Cosmetic |
| Recovery key "Next" gating | Must copy OR choose secure storage | Always enabled | Bug 3 above |
| Localization | Full i18n via `L10n` | Hardcoded English strings | Needs i18n pass eventually |
| Dehydrated devices | `enableDehydratedDevices: true` | Not configured | Could be added later |
| Session backup/restore | `initWithRestore` extension backs up OLM account | No OLM backup mechanism | Could be added later |
| Clipboard clear | On dispose only | On dispose AND on done (redundant but harmless) | No action needed |

---

## Fix Priority Order

| Priority | Bug | Effort | Impact |
|----------|-----|--------|--------|
| **P0** | Bug 4: No UIA prompt for restored sessions | Medium | Bootstrap completely broken on app restart |
| **P0** | Bug 1: `askUseExistingSsss` not auto-advanced | Trivial | Confusing prompt, risk of data loss |
| **P0** | Bug 2: `askUnlockSsss` not auto-advanced | Trivial | Confusing prompt |
| **P1** | Bug 5: No self-sign after SSSS unlock | Small | Device stays unverified |
| **P1** | Bug 6: No key re-request after bootstrap | Small | Old messages stay broken |
| **P1** | Bug 3: Recovery key "Next" not gated | Small | Users can lose their key |
| **P2** | Bug 8: No cancel confirmation | Small | Accidental backup skip |
| **P2** | Bug 7: Broad account data removal | Small | Potential data loss |
| **P2** | Bug 10: Verification flow finalization | Medium | Post-verification confusion |
| **P3** | Bug 9: No error retry | Trivial | UX improvement |

---

## Implementation Plan

### Phase 1: Critical Fixes (Bugs 1, 2, 4)

**File: `lib/widgets/bootstrap_controller.dart`**

1. Auto-advance `askUseExistingSsss`:
   - Add to the auto-advance switch block:
     ```dart
     case BootstrapState.askUseExistingSsss:
       deferredAdvance = () => bootstrap.useExistingSsss(!_wipeExisting);
       _notify();
       return;
     ```

2. Auto-advance `askUnlockSsss`:
   - Add to the auto-advance switch block:
     ```dart
     case BootstrapState.askUnlockSsss:
       deferredAdvance = () => bootstrap.unlockedSsss();
       _notify();
       return;
     ```

3. Remove `askUseExistingSsss` and `askUnlockSsss` UI from `bootstrap_views.dart` (dead code after auto-advancing).

**File: `lib/services/matrix_service.dart`** and new **UIA prompt widget**

4. Add a UIA password prompt dialog:
   - Create a listener in `BootstrapDialog` (or a parent widget) that subscribes to `matrixService.onUiaRequest`
   - Shows a password input dialog when triggered
   - Calls `matrixService.completeUiaWithPassword(request, password)`

### Phase 2: Self-Sign & Key Re-Request (Bugs 5, 6)

**File: `lib/widgets/bootstrap_controller.dart`**

5. Add self-sign after SSSS unlock in `unlockExistingSsss()`:
   ```dart
   if (encryption.crossSigning.enabled) {
     await encryption.crossSigning.selfSign(recoveryKey: key);
   }
   ```

6. Add `_decryptLastEvents()` in `onDone()`:
   ```dart
   for (final room in client.rooms) {
     final event = room.lastEvent;
     if (event != null &&
         event.type == EventTypes.Encrypted &&
         event.messageType == MessageTypes.BadEncrypted &&
         event.content['can_request_session'] == true) {
       final sessionId = event.content.tryGet<String>('session_id');
       final senderKey = event.content.tryGet<String>('sender_key');
       if (sessionId != null && senderKey != null) {
         room.client.encryption?.keyManager.maybeAutoRequest(
           room.id, sessionId, senderKey,
         );
       }
     }
   }
   ```

### Phase 3: UX Polish (Bugs 3, 7, 8, 9, 10)

7. Gate "Next" button on recovery key copy/save.
8. Restrict account data removal to known SSSS types.
9. Add cancel confirmation dialog.
10. Add retry button to error state.
11. Fix verification flow finalization to match FluffyChat's pattern.

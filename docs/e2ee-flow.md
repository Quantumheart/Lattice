# E2EE Process & User Interaction Flow

## High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        APP STARTUP                              │
│                                                                 │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────────────┐  │
│  │ Fresh     │    │ Restored     │    │ Restored Session      │  │
│  │ Login     │    │ + Stored Key │    │ No Stored Key         │  │
│  └────┬─────┘    └──────┬───────┘    └───────────┬───────────┘  │
│       │                 │                        │              │
│       ▼                 ▼                        ▼              │
│  ┌─────────┐    ┌──────────────┐    ┌───────────────────────┐   │
│  │ Sync +   │    │ Sync + Auto  │    │ Sync + Request keys   │  │
│  │ Check    │    │ Unlock       │    │ from other sessions   │  │
│  │ Backup   │    │ → Backed up  │    │ → "Not set up"        │  │
│  └────┬─────┘    └──────────────┘    └───────────┬───────────┘  │
│       │                                          │              │
│       ▼                                          ▼              │
│  User taps                              Router redirects to     │
│  "Chat backup"                          /e2ee-setup, or user   │
│  in Settings                            taps banner            │
│       │                                          │              │
│       └──────────────┬───────────────────────────┘              │
│                      ▼                                          │
│              E2EE Setup Screen                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. Login & Sync Flow

```
User enters credentials
        │
        ▼
┌───────────────────┐
│ MatrixService      │
│   .login()         │
│                    │
│ • Validate server  │
│ • Authenticate     │
│ • Cache password   │  ← stored in UiaService (30s expiry)
│   (for UIA later)  │
│ • Store credentials│
└────────┬──────────┘
         │
         ▼
┌───────────────────┐     ┌─────────────────────────┐
│ sync.startSync()   │     │ First /sync response     │
│                    │────▶│ arrives from server       │
│ await firstSync    │     │ (device keys, account     │
│                    │     │  data now available)      │
└────────┬──────────┘     └─────────────────────────┘
         │
         ▼  (onPostSyncBackup callback fires)
┌────────────────────────────────────┐
│ tryAutoUnlockBackup()              │
│                                    │
│  Stored recovery key exists?       │
│                                    │
│  NO ──▶ requestMissingRoomKeys()   │
│         (request keys from other   │
│          sessions peer-to-peer)    │
│         │                          │
│  YES ──▶ getCryptoIdentityState()  │
│          │                         │
│     ┌────┴──────┐                  │
│     │connected? │                  │
│     └────┬──────┘                  │
│    YES   │    NO                   │
│   (skip) │    ▼                    │
│     │    │ restoreCryptoIdentity() │
│     │    │ (headless bootstrap)    │
│     │    └────┬───────             │
│     │         │                    │
│     └────┬────┘                    │
│          ▼                         │
│   _restoreRoomKeys()               │
│   • loadAllKeys() from backup      │
│   • requestMissingRoomKeys()       │
│                                    │
└────────────┬───────────────────────┘
             │
             ▼
┌────────────────────────────────────┐
│ checkChatBackupStatus()            │
│                                    │
│ getCryptoIdentityState() returns:  │
│   initialized: crossSigning +      │
│                keyBackup enabled?  │
│   connected:   secrets cached      │
│                locally?            │
│                                    │
│ chatBackupNeeded =                 │
│   !initialized || !connected       │
└────────────────────────────────────┘
         │
    ┌────┴────┐
    │ needed? │
    └────┬────┘
    NO   │       YES
    ▼    │        ▼
(done)   │  Router redirects to /e2ee-setup
         │  (if !hasSkippedSetup)
         │  or KeyBackupBanner shown
```

**Source:** `lib/core/services/matrix_service.dart` — `login()`, `_activateSession()`, `_runPostLoginSync()`; `lib/core/services/sub_services/sync_service.dart` — `startSync()`, `onPostSyncBackup`; `lib/core/services/sub_services/chat_backup_service.dart` — `tryAutoUnlockBackup()`

---

## 2. E2EE Setup Screen — State Machine

```
Router redirects to /e2ee-setup
  (chatBackupNeeded == true && !hasSkippedSetup)
or user taps "Chat backup" tile in Settings
                │
                ▼
    ┌───────────────────────┐
    │   E2eeSetupScreen     │
    │                       │
    │  • Show explainer     │
    │  • User taps "Next"   │
    │  • Create controller  │
    │  • Listen for UIA     │
    │  • Start bootstrap    │
    └───────────┬───────────┘
                │
                ▼
  ┌─────────────────────────────────────────────────────────────┐
  │              SDK Bootstrap State Machine                     │
  │              (driven by BootstrapDriver)                     │
  │                                                              │
  │  AUTO-ADVANCED (no user interaction needed):                 │
  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐   │
  │  │ askWipeSsss  ├─▶│ askWipeCross ├─▶│ askSetupCross   │   │
  │  │              │  │ Signing      │  │ Signing         │   │
  │  └──────────────┘  └──────────────┘  │ (spinner)       │   │
  │                                      └────────┬────────┘   │
  │                                               │             │
  │  ┌──────────────────────┐  ┌──────────────────┴──────────┐  │
  │  │ askWipeOnlineKey     ├─▶│ askSetupOnlineKeyBackup     │  │
  │  │  Backup              │  │ (spinner)                   │  │
  │  │  (auto-detects if no │  └──────────────┬──────────────┘  │
  │  │   backup exists)     │                 │                  │
  │  └──────────────────────┘                 │                  │
  │                                           │                  │
  │  ┌──────────────┐  ┌─────────────────────┘                  │
  │  │ askBadSsss   │  │                                         │
  │  │ (ignored)    │  ▼                                         │
  │  └──────────────┘  askUseExistingSsss ──▶ askUnlockSsss     │
  │                         │                    (auto-advance)  │
  │                NEW      │      EXISTING                      │
  │                ▼        │        ▼                           │
  │       askNewSsss        │  openExistingSsss                  │
  │       (MANUAL)          │  (MANUAL)                          │
  └───────────┬─────────────┼──────────────┬─────────────────────┘
              │             │              │
              ▼             │              ▼
┌──────────────────────────┐│  ┌────────────────────────────────┐
│  "Save your recovery key" ││  │  "Unlock your backup"          │
│                           ││  │                                │
│  ┌────────────────────┐   ││  │  ┌──────────────────────────┐  │
│  │ EsJt X7wK ... 4dQm │   ││  │  │ [___________________]    │  │
│  │                     │   ││  │  │  Recovery key input      │  │
│  │  [Copy to clipboard]│   ││  │  └──────────────────────────┘  │
│  └────────────────────┘   ││  │                                │
│                           ││  │  ☑ Save key to this device     │
│  ☑ Save key to this device ││  │                                │
│                           ││  │  ─────── or ───────            │
│  ┌────────┐  ┌──────────┐ ││  │                                │
│  │ Back   │  │ Next     │ ││  │  [Verify with another device]  │
│  │        │  │ (disabled │ ││  │                                │
│  │        │  │  until key│ ││  │  [Create new key]              │
│  │        │  │  copied   │ ││  │                                │
│  │        │  │  or saved)│ ││  │  ┌────────┐  ┌─────────────┐  │
│  └────────┘  └─────┬─────┘ ││  │  │ Back   │  │ Unlock      │  │
└───────────────────┬┘ │     ││  │  └────────┘  └──────┬──────┘  │
                    │  │     │└──────────────────────────┼────────┘
                    │  │     │                      ┌────┴────┐
                    │  │     │                      │Valid key?│
                    │  │     │                      └────┬────┘
                    │  │     │                  NO  │        │ YES
                    │  │     │                  ▼   │        │
                    │  │     │           "Invalid   │        │
                    │  │     │            recovery  │        │
                    │  │     │            key"      │        │
                    └──┘     └──────────────────────┘        │
                    │                                         │
                    └──────────────────┬──────────────────────┘
                                       │
                                       ▼
                          ┌────────────────────────┐
                          │      _onDone()          │
                          │                        │
                          │ • Store recovery key   │
                          │   (if save checked,    │
                          │    new key flow only)  │
                          │ • maybeCacheAll()      │
                          │   SSSS secrets         │
                          │ • selfSign device      │
                          │ • updateUserDeviceKeys │
                          │ • signWithCross        │
                          │   Signing (backup key) │
                          │ • loadAllKeys()        │
                          │   from server backup   │
                          │ • requestMissing       │
                          │   RoomKeys()           │
                          │ • checkChatBackup      │
                          │   Status()             │
                          │ • clearCachedPassword  │
                          └───────────┬────────────┘
                                      │
                                      ▼
                          ┌─────────────────────┐
                          │   "You're all set!"  │
                          │                     │
                          │   ✅ Success icon   │
                          │                     │
                          │  "Your messages are │
                          │   backed up and     │
                          │   accessible from   │
                          │   any device."      │
                          │                     │
                          │      [Done]         │
                          └─────────┬───────────┘
                                    │
                                    ▼
                          Screen closes (context.go('/'))
```

**Source:** `lib/features/e2ee/screens/e2ee_setup_screen.dart` — screen + UI; `lib/features/e2ee/widgets/bootstrap_controller.dart` — `_onDone()` (line 198); `lib/features/e2ee/widgets/bootstrap_driver.dart` — state machine; `lib/features/e2ee/widgets/recovery_key_handler.dart` — key handling

---

## 3. Device Verification (Alternative to Recovery Key)

Triggered from the "Unlock your backup" screen via the "Verify with another device" button.
The verification runs **inline** inside the setup screen (no separate dialog).

```
User taps "Verify with another device"
    (from unlock screen)
                │
                ▼
┌──────────────────────────────────────┐
│  bootstrap_controller                │
│  .startVerification()                │
│                                      │
│  • updateUserDeviceKeys()            │
│  • Create KeyVerification            │
│    (userId/*, all devices)           │
│  • verification.start()              │
│  • phase → SetupPhase.verification   │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│  KeyVerificationInline               │
│  (rendered inside setup screen)      │
│                                      │
│  waitingAccept                       │
│  "Waiting for the other device       │
│   to accept..."                      │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│  askSas                              │
│  "Compare these emoji with the       │
│   other device"                      │
│                                      │
│  🐶  🔑  🎵  🌍  ❤️  🔒  🎉        │
│                                      │
│  [They don't match]  [They match]    │
└──────────────────┬───────────────────┘
                   │
              ┌────┴────┐
              │ Match?  │
              └────┬────┘
          NO   │       │  YES
          ▼    │       │
     (cancel,  │       ▼
      back to  │  "Verifying..."
      key input)│
               │       ▼
               │  Waits up to 10s for secrets
               │  to propagate (isCached check,
               │  1s polling)
               │       │
               │       ▼
               │   _onDone()
               │   (same as successful key entry)
               │
               └─────────────▼
                    Screen closes
```

**Source:** `lib/features/e2ee/widgets/bootstrap_controller.dart` — `startVerification()` (line 143), `onVerificationDone()` (line 163); `lib/features/e2ee/screens/e2ee_setup_screen.dart` — `KeyVerificationInline` usage

---

## 4. UIA (User-Interactive Auth) During Bootstrap

```
Bootstrap needs server-side auth
(e.g., uploading cross-signing keys)
                │
                ▼
┌──────────────────────────────────┐
│ UiaService                       │
│                                  │
│  ┌────────────────────┐          │
│  │ Cached password     │── YES ──▶ Auto-complete UIA
│  │ available?          │          (user sees nothing)
│  └────────┬───────────┘          │
│       NO  │                      │
│           ▼                      │
│  Emit via onUiaRequest stream    │
└───────────┬──────────────────────┘
            │
            ▼ (E2eeSetupScreen listens)
┌──────────────────────────────────┐
│  "Authentication required"       │
│                                  │
│  ┌──────────────────────────┐    │
│  │ Password: [____________] │    │
│  └──────────────────────────┘    │
│                                  │
│       [Cancel]    [Submit]       │
└──────────────────────────────────┘
```

**Source:** `lib/core/services/sub_services/uia_service.dart` — UIA logic; `lib/core/services/matrix_service.dart` — `uia.listenForUia()`, `uia.setCachedPassword()`; `lib/features/e2ee/screens/e2ee_setup_screen.dart` — `_showUiaPasswordPrompt()`

---

## 5. Settings — Backup Management

```
┌────────────────────────────────────────────────────────────────┐
│  SETTINGS SCREEN                                               │
│                                                                │
│  SECURITY                                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ ☁️  Chat backup                                          │  │
│  │    ├─ "Checking..."             (null — loading)         │  │
│  │    ├─ "Setting up…"             (chatBackupLoading)      │  │
│  │    ├─ "Not set up"              (true — tap → /e2ee-setup)│  │
│  │    └─ "Your keys are backed up" (false — tap → /e2ee-setup)│ │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘

All states navigate to /e2ee-setup on tap.
The E2eeSetupScreen detects chatBackupEnabled and shows the
management view ("Chat backup" / ✅) or the setup flow accordingly.

         From management view:
         ┌─────────────────────┐
         │  "Chat backup"      │
         │                     │
         │   ✅ Check icon     │
         │                     │
         │  "Your keys are     │
         │   backed up and     │
         │   accessible from   │
         │   any device."      │
         │                     │
         │  [Create new key]   │
         │  [Disable backup]   │
         └──────────┬──────────┘
                    │
          (Disable backup)
                    │
                    ▼
         ┌─────────────────────┐
         │ "Disable backup?"   │
         │                     │
         │ "Your recovery key  │
         │  and server-side    │
         │  backup will be     │
         │  deleted..."        │
         │                     │
         │  [Go back]          │
         │  [Disable backup]   │
         └──────────┬──────────┘
                    │
              (Disable)
                    │
                    ▼
         ┌──────────────────────┐
         │ disableChatBackup()  │
         │ • Delete backup from │
         │   server             │
         │ • Delete stored      │
         │   recovery key       │
         │ • chatBackupNeeded   │
         │   → true             │
         └──────────────────────┘
```

**Source:** `lib/features/settings/screens/settings_screen.dart` — backup tile (line 413); `lib/features/e2ee/screens/e2ee_setup_screen.dart` — management view; `lib/core/services/sub_services/chat_backup_service.dart` — `disableChatBackup()`

---

## 6. Logout with Backup Warning

```
User taps "Sign Out"
        │
        ▼
┌──────────────────────────────────┐
│  _confirmLogout() AlertDialog    │
│                                  │
│  ┌────────────────────────────┐  │
│  │ Backup missing?             │── YES ──▶ Show warning:
│  │ (!chatBackupEnabled)        │          ⚠️ "Your encryption
│  └────────────────────────────┘           keys are not backed
│                                           up. You will
│                                           permanently lose
│                                           access to your
│                                           encrypted messages."
└──────────────────────────────────┘
         │
         │  Actions shown:
         │  [Cancel]
         │  [Set up backup first]  ← only if backup missing
         │                           (navigates to /e2ee-setup)
         │  [Sign Out]             ← error style if backup missing,
         │                           normal style if backed up
         ▼
   matrix.logout()
   manager.removeService(matrix)
   • client.logout() (server-side)
   • Clear all session keys
   • Clear cached password
   • Delete session backup
   • Delete stored recovery key
   • Reset all state → null
```

**Source:** `lib/features/settings/screens/settings_screen.dart` — `_confirmLogout()` (line 491); `lib/core/services/matrix_service.dart` — `logout()` (line 263)

---

## Key Storage Map

```
FlutterSecureStorage (localStorage on web, Keychain/Keystore on native)
├── lattice_{clientName}_access_token   ← session credential
├── lattice_{clientName}_refresh_token  ← session credential
├── lattice_{clientName}_user_id        ← session credential
├── lattice_{clientName}_homeserver     ← session credential
├── lattice_{clientName}_device_id      ← session credential
├── lattice_session_backup_{clientName} ← JSON: tokens + olmAccount pickle
└── ssss_recovery_key_{userId}          ← recovery key (if "Save to device" checked)

In-Memory (UiaService)
└── _cachedPassword             ← login password (30s TTL)

In-Memory (ChatBackupService)
└── _chatBackupNeeded           ← null | true | false

SDK Database (IndexedDB on web, SQLite on native)
└── _client.encryption          ← OLM account, inbound group sessions,
                                   cached SSSS secrets, device keys
```

**Source:** `lib/core/services/matrix_service.dart` — `latticeKey()` helper; `lib/core/services/session_backup.dart`; `lib/core/services/sub_services/chat_backup_service.dart` — `storeRecoveryKey()`; `lib/core/services/sub_services/uia_service.dart`; `lib/core/services/client_factory_web.dart` — `MatrixSdkDatabase.init()`

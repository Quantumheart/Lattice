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
│  │ Sync +   │    │ Sync + Auto  │    │ Sync + Check          │  │
│  │ Check    │    │ Unlock       │    │ → "Not set up"        │  │
│  │ Backup   │    │ → Backed up  │    │                       │  │
│  └────┬─────┘    └──────────────┘    └───────────┬───────────┘  │
│       │                                          │              │
│       ▼                                          ▼              │
│  User taps                              User taps "Chat backup" │
│  "Chat backup"                          in Settings             │
│       │                                          │              │
│       └──────────────┬───────────────────────────┘              │
│                      ▼                                          │
│              BootstrapDialog                                    │
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
│ • Cache password   │  ← 5-min expiry timer
│   (for UIA later)  │
│ • Store credentials│
└────────┬──────────┘
         │
         ▼
┌───────────────────┐     ┌─────────────────────────┐
│ _startSync()       │     │ First /sync response     │
│                    │────▶│ arrives from server       │
│ await firstSync    │     │ (device keys, account     │
│                    │     │  data now available)      │
└────────┬──────────┘     └─────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│ checkChatBackupStatus()            │
│                                    │
│ getCryptoIdentityState() returns:  │
│   initialized: crossSigning +     │
│                keyBackup enabled?  │
│   connected:   secrets cached      │
│                locally?            │
│                                    │
│ chatBackupNeeded =                 │
│   !initialized || !connected       │
└────────┬───────────────────────────┘
         │
    ┌────┴────┐
    │ needed? │
    └────┬────┘
    YES  │        NO
    ▼    │        ▼
┌────────┴──┐  (done — "Your keys are backed up")
│ _tryAuto   │
│ Unlock()   │
└────┬───────┘
     │
     ▼
┌──────────────────────────────────────────────────┐
│ Stored recovery key exists?                       │
│                                                   │
│  NO ──────────────────────────┐                   │
│    (silent return,            │                   │
│     stays "Not set up")       │                   │
│                               │                   │
│  YES ─▶ getCryptoIdentityState│                   │
│         │                     │                   │
│    ┌────┴──────┐              │                   │
│    │connected? │              │                   │
│    └────┬──────┘              │                   │
│   YES   │    NO               │                   │
│   (skip)│    ▼                │                   │
│    │    │ restoreCrypto       │                   │
│    │    │  Identity()         │                   │
│    │    │  (headless          │                   │
│    │    │   bootstrap)        │                   │
│    │    └────┬───────         │                   │
│    │         │                │                   │
│    └────┬────┘                │                   │
│         ▼                     │                   │
│  checkChatBackupStatus()      │                   │
│  (re-check after attempt)     │                   │
└───────────────────────────────┘
```

**Source:** `lib/core/services/matrix_service.dart` — `login()` (line 130), `_startSync()` (line 281), `_tryAutoUnlockBackup()` (line 361)

---

## 2. Bootstrap Dialog — State Machine

```
User taps "Chat backup: Not set up"
                │
                ▼
    ┌───────────────────────┐
    │   BootstrapDialog     │
    │   .show(context)      │
    │                       │
    │  • Create controller  │
    │  • Listen for UIA     │
    │  • Start bootstrap    │
    └───────────┬───────────┘
                │
                ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                  SDK Bootstrap State Machine                 │
  │                                                              │
  │  AUTO-ADVANCED (no user interaction needed):                 │
  │  ┌──────────┐  ┌────────────┐  ┌───────────────────────┐    │
  │  │ loading  ├─▶│ askWipe    ├─▶│ askSetupCrossSigning  │    │
  │  └──────────┘  │ Ssss       │  │ (spinner: "Setting    │    │
  │                └────────────┘  │  up cross-signing")   │    │
  │                                └───────────┬───────────┘    │
  │                                            │                │
  │  ┌──────────────────────┐  ┌───────────────┴─────────────┐  │
  │  │ askWipeOnlineKey     ├─▶│ askSetupOnlineKeyBackup     │  │
  │  │  Backup              │  │ (spinner: "Setting up       │  │
  │  └──────────────────────┘  │  online key backup")        │  │
  │                            └───────────────┬─────────────┘  │
  │                                            │                │
  │                           ┌────────────────┴──────┐         │
  │                           │ New backup or existing?│         │
  │                           └──┬──────────────────┬─┘         │
  │                              │                  │            │
  │                    NEW SETUP │     EXISTING     │            │
  │                              ▼                  ▼            │
  │                    ┌──────────────┐  ┌──────────────────┐    │
  │                    │  askNewSsss  │  │ openExistingSsss │    │
  │                    │  (MANUAL)    │  │ (MANUAL)         │    │
  │                    └──────┬───────┘  └────────┬─────────┘    │
  │                           │                   │              │
  └───────────────────────────┼───────────────────┼──────────────┘
                              │                   │
              ┌───────────────┘                   └──────────────┐
              ▼                                                  ▼
┌──────────────────────────────┐        ┌────────────────────────────────┐
│  "Save your recovery key"    │        │  "Enter recovery key"          │
│                              │        │                                │
│  ┌────────────────────────┐  │        │  ┌──────────────────────────┐  │
│  │ EsJt X7wK ... 4dQm     │  │        │  │ [___________________]    │  │
│  │                         │  │        │  │  Recovery key input      │  │
│  │  [Copy to clipboard]   │  │        │  └──────────────────────────┘  │
│  └────────────────────────┘  │        │                                │
│                              │        │  ☑ Save key to this device     │
│  ☑ Save key to this device   │        │                                │
│                              │        │  ─────── or ───────            │
│  ┌────────┐  ┌────────────┐  │        │                                │
│  │ Cancel │  │ Next       │  │        │  [Verify with another          │
│  │        │  │ (disabled   │  │        │      device]                   │
│  │        │  │  until key  │  │        │                                │
│  │        │  │  copied or  │  │        │  [Lost recovery key?]          │
│  │        │  │  saved)     │  │        │                                │
│  └────────┘  └─────┬──────┘  │        │  ┌────────┐  ┌─────────────┐  │
│                     │        │        │  │ Cancel │  │ Unlock      │  │
└─────────────────────┼────────┘        │  └────────┘  └──────┬──────┘  │
                      │                 └──────────────────────┼────────┘
                      │                                        │
                      │              ┌─────────────────────────┘
                      │              │
                      │         ┌────┴────┐
                      │         │Valid key?│
                      │         └────┬────┘
                      │         NO   │   YES
                      │         ▼    │    │
                      │    "Invalid  │    │
                      │     recovery │    │
                      │     key"     │    │
                      │              │    │
                      └──────┬───────┘    │
                             │            │
                             ▼            │
                    ┌─────────────────────┴──┐
                    │      onDone()          │
                    │                        │
                    │ • Store recovery key   │
                    │   (if save checked)    │
                    │ • Cache SSSS secrets   │
                    │ • Self-sign device     │
                    │ • Update device keys   │
                    │ • Re-request keys for  │
                    │   undecryptable msgs   │
                    │ • Check backup status  │
                    │ • Clear cached password│
                    └───────────┬────────────┘
                                │
                                ▼
                    ┌─────────────────────┐
                    │  "Backup complete"  │
                    │                     │
                    │   ✅ Success icon   │
                    │                     │
                    │  "Your chat backup  │
                    │   has been set up"  │
                    │                     │
                    │      [Done]         │
                    └─────────┬───────────┘
                              │
                              ▼
                     Dialog closes,
                     Settings tile →
                     "Your keys are backed up"
```

**Source:** `lib/features/e2ee/widgets/bootstrap_controller.dart` — state machine (line 149), `onDone()` (line 378); `lib/features/e2ee/widgets/bootstrap_views.dart` — UI rendering; `lib/features/e2ee/widgets/bootstrap_dialog.dart` — dialog orchestration

---

## 3. Device Verification (Alternative to Recovery Key)

```
User taps "Verify with another device"
    (from openExistingSsss view)
                │
                ▼
┌──────────────────────────────────────┐
│  KeyVerificationDialog               │
│                                      │
│  waitingAccept                       │
│  "Waiting for the other device       │
│   to accept..."                      │
│  ┌─────────────────────────────┐     │
│  │        ⏳ Spinner            │     │
│  └─────────────────────────────┘     │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│  askSas                              │
│  "Compare these emoji with the       │
│   other device"                      │
│                                      │
│  ┌─────────────────────────────────┐ │
│  │  🐶  🔑  🎵  🌍  ❤️  🔒  🎉   │ │
│  │  Dog Key Music Globe Heart Lock │ │
│  └─────────────────────────────────┘ │
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
      return   │  ┌──────────────────┐
      to key   │  │ waitingSas       │
      input)   │  │ "Verifying..."   │
               │  └────────┬─────────┘
               │           │
               │           ▼
               │  ┌──────────────────────────────┐
               │  │ done                          │
               │  │ "Device verified              │
               │  │  successfully!"               │
               │  │                               │
               │  │ Wait for secrets to propagate │
               │  │ (30s timeout on               │
               │  │  onSecretStored stream)       │
               │  │                               │
               │  │         [Done]                │
               │  └──────────┬───────────────────┘
               │             │
               │             ▼
               │   Bootstrap auto-finalized
               │   via onDone()
               │             │
               └─────────────▼
                    Dialog closes
```

**Source:** `lib/features/e2ee/widgets/key_verification_dialog.dart` — states (line 29), SAS auto-selection (line 56); `lib/features/e2ee/widgets/bootstrap_dialog.dart` — `_showVerificationDialog()` (line 156)

---

## 4. UIA (User-Interactive Auth) During Bootstrap

```
Bootstrap needs server-side auth
(e.g., uploading cross-signing keys)
                │
                ▼
┌──────────────────────────────────┐
│ MatrixService._handleUiaRequest  │
│                                  │
│  ┌────────────────────┐          │
│  │ Cached password     │── YES ──▶ Auto-complete UIA
│  │ available?          │          (user sees nothing)
│  └────────┬───────────┘          │
│       NO  │                      │
│           ▼                      │
│  ┌────────────────────────────┐  │
│  │ Forward to UI via          │  │
│  │ onUiaRequest stream        │  │
│  └────────────┬───────────────┘  │
│               │                  │
└───────────────┼──────────────────┘
                ▼
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

**Source:** `lib/core/services/matrix_service.dart` — `_handleUiaRequest()` (line 215), `_setCachedPassword()` (line 261)

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
│  │    ├─ "Not set up"              (true — tap → Bootstrap) │  │
│  │    └─ "Your keys are backed up" (false — tap → Info)     │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘

         │                              │
    (Not set up)                  (Backed up)
         │                              │
         ▼                              ▼
  BootstrapDialog            ┌─────────────────────┐
  (see §2 above)             │  "Chat backup"      │
                             │                     │
                             │   ✅ Check icon     │
                             │                     │
                             │  "Your keys are     │
                             │   backed up and     │
                             │   accessible from   │
                             │   any device."      │
                             │                     │
                             │  [Disable backup]   │
                             │  [OK]               │
                             └──────────┬──────────┘
                                        │
                              (Disable backup)
                                        │
                                        ▼
                             ┌─────────────────────┐
                             │ "Disable chat        │
                             │  backup?"            │
                             │                      │
                             │ "You will lose       │
                             │  access to encrypted │
                             │  history on new      │
                             │  devices."           │
                             │                      │
                             │  [Cancel]  [Disable] │
                             └──────────┬───────────┘
                                        │
                                  (Disable)
                                        │
                                        ▼
                             ┌──────────────────────┐
                             │ disableChatBackup()   │
                             │ • Delete backup from  │
                             │   server              │
                             │ • Delete stored       │
                             │   recovery key        │
                             │ • Set status →        │
                             │   "Not set up"        │
                             └──────────────────────┘
```

**Source:** `lib/features/settings/screens/settings_screen.dart` — backup tile (line 109), `_showBackupInfo()` (line 182), `_confirmDisableBackup()` (line 223)

---

## 6. Logout with Backup Warning

```
User taps "Sign Out"
        │
        ▼
   ┌────┴──────────┐
   │ Backup enabled?│
   └────┬──────────┘
   YES  │       NO
   │    │        │
   │    │        ▼
   │    │  ┌─────────────────────────────────┐
   │    │  │  ⚠️  "Your encryption keys are  │
   │    │  │  not backed up. You will         │
   │    │  │  permanently lose access to      │
   │    │  │  your encrypted messages."       │
   │    │  │                                  │
   │    │  │  [Set up backup first]           │
   │    │  │  [Cancel]                        │
   │    │  │  [Sign Out] (red/error style)    │
   │    │  └──────────┬──────────────────────┘
   │    │             │
   │    │    ┌────────┴──────────┐
   │    │    │                   │
   │    │ (setup)          (sign out)
   │    │    │                   │
   │    │    ▼                   │
   │    │  Bootstrap             │
   │    │  Dialog                │
   │    │                        │
   ▼    │                        │
┌───────┴────────┐               │
│ Standard logout │               │
│ confirmation    │◀──────────────┘
│                 │
│ [Cancel]        │
│ [Sign Out]      │
└────────┬────────┘
         │
         ▼
   MatrixService.logout()
   • client.logout()
   • Clear all session keys
   • Clear cached password
   • Reset all state → null
```

**Source:** `lib/features/settings/screens/settings_screen.dart` — `_confirmLogout()` (line 254); `lib/core/services/matrix_service.dart` — `logout()` (line 183)

---

## Key Storage Map

```
FlutterSecureStorage
├── lattice_access_token        ← session credential
├── lattice_user_id             ← session credential
├── lattice_homeserver          ← session credential
├── lattice_device_id           ← session credential
└── ssss_recovery_key_{userId}  ← recovery key (if "Save to device" checked)

In-Memory (MatrixService)
├── _cachedPassword             ← login password (5-min TTL)
├── _chatBackupNeeded           ← null | true | false
└── _client.encryption          ← SDK manages cached SSSS secrets
```

**Source:** `lib/core/services/matrix_service.dart` — storage keys (line 316), recovery key (line 389), password caching (line 261)

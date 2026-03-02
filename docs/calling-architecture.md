# Voice & Video Calling — Architecture Diagrams

## 1. System Architecture — How the pieces connect

```
┌─────────────────────────────────────────────────────────────────────┐
│                        LATTICE (Flutter)                            │
│                                                                     │
│  ┌──────────────┐    ┌──────────────────┐    ┌───────────────────┐  │
│  │ MatrixService │    │   CallService    │    │   In-Call UI      │  │
│  │              │    │  (ChangeNotifier) │    │                   │  │
│  │ - sync       │◄──►│ - callState      │◄──►│ - video grid      │  │
│  │ - rooms      │    │ - participants   │    │ - controls        │  │
│  │ - events     │    │ - local tracks   │    │ - PiP             │  │
│  │ - auth       │    │ - remote tracks  │    │ - screen share    │  │
│  └──────┬───────┘    └───┬──────────┬───┘    └───────────────────┘  │
│         │                │          │                                │
│         │   signaling    │          │  media                        │
└─────────┼────────────────┼──────────┼───────────────────────────────┘
          │                │          │
          ▼                ▼          ▼
┌─────────────────┐  ┌──────────────────────────────────┐
│  Matrix Server   │  │        LiveKit Server             │
│  (Synapse/etc)   │  │                                   │
│                  │  │  ┌─────┐  ┌─────┐  ┌─────┐       │
│  m.call.member   │  │  │ SFU │──│Track│──│Track│       │
│  state events    │──►  │     │  │ Sub │  │ Pub │       │
│  (room, token,   │  │  └──┬──┘  └─────┘  └─────┘       │
│   livekit URL)   │  │     │                             │
└─────────────────┘  └─────┼─────────────────────────────┘
                           │
                    ┌──────┴──────┐
                    │  WebRTC     │
                    │  UDP/TCP    │
                    │  (DTLS/SRTP)│
                    └─────────────┘
```

## 2. MatrixRTC Call Signaling Flow

```
     Alice (Lattice)              Matrix Server            LiveKit Server           Bob (Lattice)
          │                            │                        │                        │
          │  1. PUT m.call.member       │                        │                        │
          │  { livekit_service_url,     │                        │                        │
          │    device_id, focus }       │                        │                        │
          │───────────────────────────►│                        │                        │
          │                            │                        │                        │
          │                            │  2. sync event         │                        │
          │                            │───────────────────────────────────────────────►│
          │                            │                        │                        │
          │  3. GET /_livekit/token     │                        │                        │
          │───────────────────────────►│                        │                        │
          │◄───────────────────────────│                        │                        │
          │     { access_token }       │                        │                        │
          │                            │                        │                        │
          │  4. Connect (WSS)          │                        │                        │
          │─────────────────────────────────────────────────────►                        │
          │◄─────────────────────────────────────────────────────│                        │
          │     room joined            │                        │                        │
          │                            │                        │                        │
          │  5. Publish audio+video    │                        │                        │
          │═══════════════════════════════════════════════════►│                        │
          │                            │                        │                        │
          │                            │                        │  6. Bob reads           │
          │                            │                        │     m.call.member,      │
          │                            │                        │     gets LK token,      │
          │                            │                        │     connects             │
          │                            │                        │◄═══════════════════════│
          │                            │                        │                        │
          │  7. Subscribe to Bob       │                        │  7. Subscribe to Alice  │
          │◄══════════════════════════════════════════════════►│                        │
          │                            │                        │═══════════════════════►│
          │                            │                        │                        │
          │             ═══ media (WebRTC via SFU) ═══         │                        │
          │                            │                        │                        │
          │  8. DELETE m.call.member    │                        │                        │
          │  (hangup)                  │                        │                        │
          │───────────────────────────►│                        │                        │
          │  9. Disconnect             │                        │                        │
          │─────────────────────────────────────────────────────►                        │
          │                            │  10. sync: member left │                        │
          │                            │───────────────────────────────────────────────►│
          │                            │                        │                        │
```

## 3. CallService State Machine

```
                          ┌─────────────────────────────┐
                          │                             │
                          ▼                             │
                    ┌───────────┐                       │
         ┌────────│   IDLE    │◄──────────────┐       │
         │         └─────┬─────┘               │       │
         │               │                     │       │
         │        joinCall(roomId)              │       │
         │               │                     │       │
         │               ▼                     │       │
         │        ┌─────────────┐              │       │
         │        │  JOINING    │              │       │
         │        │             │              │       │
         │        │ - fetch LK  │       leaveCall()    │
         │        │   token     │         or           │
         │        │ - send      │       error          │
         │        │   m.call.   │              │       │
         │        │   member    │              │       │
         │        └──────┬──────┘              │       │
         │               │                     │       │
         │          LK connected               │       │
         │               │                     │       │
         │               ▼                     │       │
         │        ┌─────────────┐              │       │
         │        │ CONNECTED   │──────────────┘       │
         │        │             │                       │
         │        │ - tracks    │    network drop       │
         │        │   published │──────────┐           │
         │        │ - receiving │          │           │
         │        │   remotes   │          ▼           │
         │        │             │   ┌──────────────┐   │
         │        │ actions:    │   │ RECONNECTING │   │
         │        │  toggleMic  │   │              │───┘
         │        │  toggleCam  │   │ - retry x3   │  recovered
         │        │  toggleSS   │   │ - backoff    │───────┐
         │        │  leaveCall  │   └──────┬───────┘       │
         │        └──────┬──────┘          │               │
         │               │            give up              │
         │        leaveCall()              │               │
         │               │                ▼               │
         │               ▼         ┌──────────────┐       │
         │        ┌──────────────┐ │   FAILED     │       │
         │        │DISCONNECTING │ │              │       │
         │        │              │ │ - show error │       │
         │        │ - rm state   │ │ - cleanup    │       │
         │        │   event      │ └──────┬───────┘       │
         │        │ - close LK   │        │               │
         │        │ - cleanup    │        │               │
         │        └──────┬───────┘        │               │
         │               │               │               │
         │               ▼               │               │
         │        ┌───────────┐          │               │
         └───────►│   IDLE    │◄─────────┘               │
                  └───────────┘◄──────────────────────────┘
```

## 4. Responsive In-Call UI Layouts

```
MOBILE (<720px)                TABLET (720-1100px)           DESKTOP (>=1100px)
Full-screen overlay            Call replaces chat pane       Call within 3-column layout

+------------------+     +------+-----------------+    +----+------+------------------+
| < Room Name  ... |     |      |  Room Name   ...|    |    |      |  Room Name   ... |
+------------------+     |      +-----------------+    |    |      +------------------+
|                  |     |      |                 |    |    |      |                  |
|  +------------+  |     |      | +-----++-----+ |    |    |      | +-----+ +-----+  |
|  |            |  |     |      | |     ||     | |    | S  | Room | |     | |     |  |
|  |   Remote   |  |     | Rail | | Ali || Bob | |    | p  | List | | Ali | | Bob |  |
|  |   Video    |  |     |      | |     ||     | |    | a  |      | |     | |     |  |
|  |            |  |     |      | +-----++-----+ |    | c  | ---- | +-----+ +-----+  |
|  |            |  |     |      |                 |    | e  | #gen |                  |
|  +------------+  |     |      | +-----++-----+ |    |    | #dev | +-----+ +-----+  |
|                  |     |      | |     ||     | |    | R  | #ran | |     | |     |  |
|  +----+          |     |      | | Car || Dan | |    | a  | ---- | | Car | | Dan |  |
|  | Me | (PiP)   |     |      | |     ||     | |    | i  | @joe | |     | |     |  |
|  +----+          |     |      | +-----++-----+ |    | l  | @sam | +-----+ +-----+  |
|                  |     |      |                 |    |    |      |                  |
+------------------+     |      +-----------------+    |    |      +------------------+
|                  |     |      |                 |    |    |      |                  |
| [mic][cam][ss][X]|     |      |[mic][cam][ss][X]|    |    |      |[mic][cam][ss][X] |
|                  |     |      |                 |    |    |      |                  |
+------------------+     +------+-----------------+    +----+------+------------------+

SCREEN SHARE ACTIVE (desktop):

+----+------+------------------------------------+
|    |      |  Room Name                     ... |
|    |      +------------------------------------+
|    |      |                                    |
| S  | Room |  +------------------------------+  |
| p  | List |  |                              |  |
| a  |      |  |     Alice's Screen           |  |
| c  |      |  |     (shared screen - large)  |  |
| e  |      |  |                              |  |
|    |      |  +------------------------------+  |
| R  |      |  +------+ +------+ +------+       |
| a  |      |  | Ali  | | Bob  | | Car  | strip |
| i  |      |  +------+ +------+ +------+       |
| l  |      +------------------------------------+
|    |      |      [mic][cam][ss][X]              |
+----+------+------------------------------------+
```

## 5. Phase 2 — Native WebRTC 1:1 Fallback Decision Tree

```
    User taps "Call" button
              |
              v
    +-------------------+
    | Check room type   |
    +--------+----------+
             |
     +-------+--------+
     |                |
  DM (1:1)      Group room
     |                |
     v                v
+--------------+  +-----------------+
| LiveKit       |  | LiveKit          |
| configured?   |  | configured?      |
+---+------+---+  +---+---------+---+
    |      |          |         |
   YES     NO        YES        NO
    |      |          |         |
    v      v          v         v
  +----+ +--------+ +----+  +------------+
  | LK | | P2P    | | LK |  | "Group     |
  |    | | WebRTC | |    |  |  calls need |
  +--+-+ +---+----+ +-+--+  |  LiveKit"  |
     |       |        |     +------------+
     v       v        v
+------------------------------------------------------------+
|                                                            |
|                   LIVEKIT PATH                             |
|                                                            |
|  1. Read m.call.member state events from room              |
|  2. GET /_livekit/token from homeserver                    |
|  3. Connect to LiveKit server (WSS)                        |
|  4. Publish local tracks -> SFU fans out to participants   |
|  5. Subscribe to remote tracks                             |
|  6. On hangup: DELETE m.call.member + disconnect           |
|                                                            |
|  Supports: 1:1, group, screen share                        |
|  Requires: LiveKit server                                  |
|                                                            |
+------------------------------------------------------------+

+------------------------------------------------------------+
|                                                            |
|               NATIVE WebRTC PATH (Phase 2)                 |
|                                                            |
|  1. Fetch TURN/STUN from /_matrix/client/v3/voip/turnServer|
|  2. Create RTCPeerConnection                               |
|  3. Send m.call.invite (SDP offer via Matrix room event)   |
|  4. Receive m.call.answer (SDP answer)                     |
|  5. Exchange m.call.candidates (ICE)                       |
|  6. Direct P2P media flow (no SFU)                         |
|  7. On hangup: send m.call.hangup event                    |
|                                                            |
|  Supports: 1:1 only, audio+video                           |
|  Requires: nothing extra (just homeserver)                  |
|                                                            |
+------------------------------------------------------------+
```

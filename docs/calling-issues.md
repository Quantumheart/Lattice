# Voice & Video Calling — GitHub Issues

## Issue 1: [Epic] Voice & Video Calling

**Title:** `feat: Voice & video calling with LiveKit and WebRTC`

**Labels:** `enhancement`, `epic`

### Description

#### Summary
Add voice/video calling to Lattice with screen sharing support across all platforms (Linux, Windows, Android, iOS, macOS, Web).

#### Approach
Two phases:
1. **LiveKit (MatrixRTC / MSC3401)** — SFU-based calling for both 1:1 and group calls. Uses `livekit_client` + `flutter_webrtc` packages. Requires a LiveKit server paired with the homeserver.
2. **Native WebRTC (legacy m.call.\*)** — Peer-to-peer 1:1 calls as a fallback when no LiveKit server is available.

#### Features
- [ ] #2 — Dependencies & platform configuration
- [ ] #3 — CallService with MatrixRTC signaling
- [ ] #4 — In-call UI (video grid, controls)
- [ ] #5 — Call initiation & incoming call flows
- [ ] #6 — Screen sharing
- [ ] #7 — Native WebRTC 1:1 calls (Phase 2)

#### Architecture
- New `CallMixin` on `MatrixService` (or standalone `CallService` as ChangeNotifier)
- Follows existing patterns: service layer → controller → UI
- LiveKit room lifecycle managed alongside Matrix room state

---

## Issue 2: Add calling dependencies and platform configuration

**Title:** `feat: Add calling dependencies and platform configuration`

**Labels:** `enhancement`, `calling`

### Description

#### Summary
Add the SDK dependencies and platform-specific configuration required for voice/video calling.

#### Dependencies to add
- `livekit_client` — LiveKit Flutter SDK
- `flutter_webrtc` — WebRTC primitives (camera, mic, peer connections)
- `callkeep` or platform-specific packages for native call UI integration

#### Platform configuration

##### Android
- Permissions: `CAMERA`, `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, `BLUETOOTH_CONNECT`
- Foreground service for active calls
- ConnectionService integration for incoming call notifications

##### iOS
- Permissions: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`
- CallKit integration for native call UI
- Background mode: `voip`, `audio`
- Push notification entitlement for VoIP pushes

##### Linux
- PipeWire/PulseAudio audio access
- Screen capture permissions (portal API)

##### Windows
- Camera/microphone access via WinRT APIs
- No special permissions required (user prompt handled by OS)

##### macOS
- Permissions: camera, microphone entitlements
- Sandbox configuration

##### Web
- `getUserMedia` permissions (handled by browser)

#### Acceptance criteria
- [ ] `flutter pub get` succeeds on all platforms
- [ ] Camera/mic permissions can be requested and granted
- [ ] LiveKit client can connect to a test LiveKit server
- [ ] App still builds and existing tests pass

---

## Issue 3: Create CallService with MatrixRTC signaling

**Title:** `feat: Create CallService with MatrixRTC/LiveKit signaling`

**Labels:** `enhancement`, `calling`

### Description

#### Summary
Build the core service layer that bridges Matrix room state events (MatrixRTC / MSC3401) with LiveKit room connections.

#### Design
Follow the existing mixin pattern — either a `CallMixin` on `MatrixService` or a standalone `CallService` (ChangeNotifier) provided via Provider.

##### State machine
```
idle → joining → connected → disconnecting → idle
                    ↓
               reconnecting
```

##### Responsibilities
- Listen for MatrixRTC state events (`m.call.member`) in rooms
- Extract LiveKit connection info (server URL, access token) from state events
- Manage `LiveKitRoom` lifecycle: connect, publish tracks, subscribe to remote tracks
- Expose observable state: `CallState`, active participants, local/remote tracks
- Handle call membership (join/leave call in a room)
- Track audio/video mute state, active speaker detection
- Clean up resources on disconnect or room leave

##### Key interfaces
```dart
// Observable state
CallState get callState; // idle, joining, connected, etc.
Room? get activeRoom; // current Matrix room with active call
List<RemoteParticipant> get participants;
bool get isMicEnabled;
bool get isCameraEnabled;
bool get isScreenShareEnabled;

// Actions
Future<void> joinCall(String roomId);
Future<void> leaveCall();
void toggleMicrophone();
void toggleCamera();
Future<void> toggleScreenShare();
```

#### Acceptance criteria
- [ ] Can join a MatrixRTC call in a room and connect to LiveKit
- [ ] Local audio/video tracks are published
- [ ] Remote participant tracks are received
- [ ] Call state transitions are correct and observable
- [ ] Clean disconnect on leave or room change
- [ ] Unit tests for state transitions with mocked LiveKit/Matrix

---

## Issue 4: Build in-call UI

**Title:** `feat: Build in-call UI with video grid and controls`

**Labels:** `enhancement`, `calling`, `ui`

### Description

#### Summary
Build the in-call screen that displays video feeds and call controls. Must be responsive across all three layout breakpoints.

#### UI components

##### Video grid
- Adaptive grid layout based on participant count
- 1 participant: full-screen self-view
- 2 participants: side-by-side (desktop) or stacked (mobile)
- 3+ participants: grid with pagination or scrolling
- Local camera preview (picture-in-picture or grid tile)
- Name labels and audio level indicators on tiles
- Active speaker highlight

##### Control bar
- Mute/unmute microphone
- Enable/disable camera
- Screen share toggle
- Hang up button
- Audio device selector (speaker/headphones/bluetooth)
- Camera flip (mobile)

##### Layout integration
- **Mobile (<720px):** Full-screen overlay on top of chat, swipe down to minimize to PiP
- **Tablet (720–1100px):** Call replaces chat pane, or overlay
- **Desktop (≥1100px):** Call pane replaces or overlays chat area within the 3-column layout

##### States
- Joining/connecting: spinner + "Connecting..." text
- Connected: video grid + controls
- Reconnecting: overlay with reconnection indicator
- Call ended: brief summary, auto-dismiss

#### Acceptance criteria
- [ ] Video grid renders correctly for 1–6+ participants
- [ ] All control buttons work and reflect current state
- [ ] Responsive layout works at all three breakpoints
- [ ] Graceful handling of camera/mic permission denials
- [ ] Follows Material You theming

---

## Issue 5: Implement call initiation and incoming call flows

**Title:** `feat: Implement call ringing, incoming call, and call history`

**Labels:** `enhancement`, `calling`, `ui`

### Description

#### Summary
Implement the flows for starting a call, receiving an incoming call, and showing call status in the room list / chat.

#### Outgoing call flow
- "Call" button in chat app bar (voice and video options)
- Ringing state UI while waiting for the other party
- Timeout after 30–60s with "No answer" state
- Cancel button during ringing

#### Incoming call flow
- Incoming call dialog/overlay (caller avatar, name, room)
- Accept (audio) / Accept (video) / Decline buttons
- Ring sound + vibration (mobile)
- **iOS:** CallKit incoming call screen (works from lock screen)
- **Android:** ConnectionService high-priority notification
- **Desktop:** System notification + in-app dialog

#### Room integration
- Call indicator in room list (icon showing active call in a room)
- "Join call" button when a call is active in current room
- Participant count badge on active calls
- Call events in chat timeline ("Alice started a call", "Call ended — 5:32")

#### Acceptance criteria
- [ ] Can initiate a call from chat screen
- [ ] Incoming calls show a dialog with accept/decline
- [ ] Platform-native call UI on iOS (CallKit) and Android (ConnectionService)
- [ ] Active call indicator visible in room list
- [ ] Call events rendered in chat timeline

---

## Issue 6: Add screen sharing support

**Title:** `feat: Add screen sharing support in calls`

**Labels:** `enhancement`, `calling`

### Description

#### Summary
Add the ability to share your screen during a call, and view other participants' screen shares.

#### Sharing
- Toggle button in call controls
- Publish screen capture track to LiveKit room alongside (or replacing) camera track
- Platform-specific capture:
  - **Android:** MediaProjection API (requires user permission dialog)
  - **iOS:** ReplayKit broadcast extension
  - **Linux:** PipeWire/X11 screen capture via xdg-desktop-portal
  - **Windows:** Screen capture via WGC (Windows Graphics Capture) API
  - **macOS:** Screen capture entitlement + permission
  - **Web:** `getDisplayMedia()` browser API

#### Viewing
- Screen share track displayed as a large/primary tile in the video grid
- Other video feeds shrink to a filmstrip or sidebar
- Screen share participant name label: "Alice's screen"

#### Edge cases
- Only one screen share active per user at a time
- Handle permission denial gracefully
- Stop sharing automatically on call end or app background (mobile)

#### Acceptance criteria
- [ ] Can share screen on each platform
- [ ] Screen share visible to other participants as a distinct tile
- [ ] UI adapts layout when screen share is active vs not
- [ ] Stop share works cleanly

---

## Issue 7: Implement native WebRTC for 1:1 calls (Phase 2)

**Title:** `feat: Native WebRTC peer-to-peer 1:1 calls`

**Labels:** `enhancement`, `calling`, `phase-2`

### Description

#### Summary
Add support for 1:1 peer-to-peer calls using the legacy Matrix VoIP spec (`m.call.invite`, `m.call.answer`, `m.call.candidates`, `m.call.hangup`). This serves as a fallback when no LiveKit server is configured.

#### Why
- Not all homeservers have a LiveKit instance
- 1:1 calls don't need an SFU — direct peer-to-peer is simpler and lower latency
- Compatibility with other Matrix clients that only support legacy VoIP

#### Implementation
- Use `flutter_webrtc` directly (no LiveKit)
- Handle Matrix call events: `m.call.invite`, `m.call.answer`, `m.call.candidates`, `m.call.hangup`, `m.call.reject`
- ICE candidate exchange via Matrix room events
- TURN/STUN server configuration from homeserver `.well-known` or `/_matrix/client/v3/voip/turnServer`
- Reuse the same in-call UI from Issue #4 (just different backend)
- Auto-detect: if LiveKit is available for a room, prefer it; otherwise fall back to native WebRTC

#### Scope
- 1:1 direct calls only (not group)
- Audio + video (reuse screen share from Issue #6 if feasible over p2p)

#### Acceptance criteria
- [ ] Can place and receive 1:1 calls without a LiveKit server
- [ ] ICE negotiation completes and media flows
- [ ] TURN server fetched from homeserver
- [ ] Graceful fallback: LiveKit preferred when available, WebRTC otherwise
- [ ] Interop tested with at least one other Matrix client (Element, FluffyChat, etc.)

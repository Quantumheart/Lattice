---
name: "feat: IRC-Style Message Layout"
about: Add a flat, dense message layout as an alternative to the current bubble style
title: "feat: Add IRC-style message layout option"
labels: enhancement, chat, layout
---

## Summary

Add an alternative "IRC-style" message layout that displays messages as flat, dense rows instead of the current bubble style. This layout prioritizes information density and readability, especially for power users managing many rooms.

## Proposed Design

```
 BUBBLE STYLE (current)               IRC STYLE (new option)
┌──────────────────────────┐  ┌──────────────────────────────────┐
│                          │  │                                  │
│   ┌──────────────────┐   │  │  10:30  Alice   Hey, are you    │
│   │ Hey, are you free│   │  │                 free tonight?    │
│   │ tonight?          │   │  │  10:32  You     Sure! Let's do  │
│   └──────────────────┘   │  │                 7pm?             │
│                          │  │  10:33  Alice   Sounds great 👍   │
│      ┌─────────────────┐ │  │  10:45  Bob     Anyone want to   │
│      │ Sure! Let's do  │ │  │                 grab lunch?      │
│      │ 7pm?             │ │  │  10:46  You     I'm in!         │
│      └─────────────────┘ │  │  10:47  Carol   Me too           │
│                          │  │  ─────── Today ───────           │
│   ┌──────────────────┐   │  │  09:01  Alice   Good morning!    │
│   │ Sounds great 👍   │   │  │  09:05  You     Morning!        │
│   └──────────────────┘   │  │                                  │
├──────────────────────────┤  ├──────────────────────────────────┤
│ 💬 Type a message...  📎 │  │ 💬 Type a message...          📎 │
└──────────────────────────┘  └──────────────────────────────────┘
  rounded bubbles, grouped       flat rows, timestamps visible,
  by sender, colorized           monospace-friendly, dense
```

## Details

### Row structure
Each message is a single flat row:
```
[HH:MM]  SenderName   Message content here
                       Continuation lines wrap and indent
```

- **Timestamp:** Always visible, left-aligned, muted color (`onSurfaceVariant`)
- **Sender name:** Fixed-width column, color-coded by user (consistent with current avatar colors)
- **Message body:** Left-aligned after sender column, wraps naturally
- **No bubbles:** No background decoration, no border radius, no elevation
- **No avatars:** Sender identified by name color alone (saves horizontal space)
- **Grouped messages:** Consecutive messages from the same sender omit the name, showing only timestamp + indented text
- **Hover state:** Subtle background highlight on the full row

### Density
- Vertical padding: 2px between messages (vs. 8-16px in bubble mode)
- Messages from the same sender within 2 minutes are grouped with no extra spacing
- Date separators as centered horizontal rules with date label

### Interaction
- Long-press / right-click shows the same context menu as bubble mode
- Reply indicator shown as `↳ re: [preview]` prefix on the line
- Reactions displayed inline after the message: `message text  [👍 2] [❤️ 1]`

## Implementation Notes

- Add a `MessageLayout` enum: `bubble` (default), `irc`
- Add to `PreferencesService` with `SharedPreferences` persistence
- Create a new `IrcMessageRow` widget as an alternative to `MessageBubble`
- In `ChatScreen`, switch between `MessageBubble` and `IrcMessageRow` based on the preference
- Reuse existing `_DensityMetrics` pattern — add IRC-specific metrics
- Wire the layout picker into `SettingsScreen` alongside the existing density picker

## Files likely affected

- `lib/widgets/message_bubble.dart` — extract shared logic, or keep separate
- `lib/widgets/irc_message_row.dart` — **new file** for the IRC row widget
- `lib/screens/chat_screen.dart` — conditional widget selection
- `lib/services/preferences_service.dart` — `MessageLayout` enum + persistence
- `lib/screens/settings_screen.dart` — layout picker in Preferences section

## Pairs well with

- Classic/Retro IRC theme (#classic-retro-theme) — combining both gives a full retro experience
- Compact density setting — IRC style + compact density = maximum information density

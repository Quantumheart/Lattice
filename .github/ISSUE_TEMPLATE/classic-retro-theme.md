---
name: "feat: Classic/Retro IRC Theme Variant"
about: Add an alternative IRC-inspired theme with flat colors, sharp corners, and monospace typography
title: "feat: Add classic/retro IRC theme variant"
labels: enhancement, theme
---

## Summary

Add an alternative "Classic / Retro" theme that gives the app an IRC-inspired aesthetic, appealing to power users and long-time Matrix users who prefer a minimal, information-dense look.

## Proposed Design

```
┌──────────────────────────────────────┐
│  Lattice — #dev-room                 │
├──────────────────────────────────────┤
│                                      │
│  [10:30] <Alice>  PR merged!         │
│  [10:32] <Bob>    LGTM               │
│  [10:33] <Alice>  Thanks 👍           │
│  [10:45] <Carol>  Anyone for lunch?  │
│  [10:46] <You>    I'm in!            │
│                                      │
├──────────────────────────────────────┤
│ > Type a message...                  │
└──────────────────────────────────────┘
  Flat colors, sharp corners, monospace
```

## Details

- **Sharp corners:** `borderRadius: 0` on cards, inputs, buttons, and bubbles
- **Flat surfaces:** Zero elevation, no shadows, minimal layering
- **Monospace typography:** Use a monospace font family (e.g., `JetBrains Mono`, `Fira Code`, or system monospace) for all text
- **Muted color palette:** Desaturated greens, ambers, and grays inspired by classic terminal themes
- **Reduced chrome:** Minimal padding, no avatars by default, dense information layout
- **Light variant:** Light gray background, dark text, subtle green/amber accents
- **Dark variant:** Near-black background (#1a1a2e or #0d1117), green-on-black terminal feel

## Implementation Notes

- Add a new `LatticeTheme.classic()` static factory method alongside the existing `.light()` and `.dark()` factories
- Add a `ThemeVariant` enum (`material`, `classic`) to `PreferencesService`
- Wire the variant selector into `SettingsScreen` under Preferences
- The classic theme should still support light/dark brightness modes
- Consider bundling a monospace font or using the system default

## Files likely affected

- `lib/theme/lattice_theme.dart` — new `classic()` factory + monospace `_textTheme`
- `lib/services/preferences_service.dart` — new `ThemeVariant` enum + persistence
- `lib/screens/settings_screen.dart` — variant picker UI
- `lib/main.dart` — wire variant into `MaterialApp` theme selection
- `pubspec.yaml` — optional monospace font asset

# Plan: Classic/Retro IRC Theme Variant (Issue #19)

## Summary

Add an alternative "Classic" theme variant inspired by classic IRC/terminal interfaces, with sharp corners, monospace fonts, flat surfaces, desaturated terminal colors, and minimal padding. The variant works alongside the existing light/dark brightness toggle.

---

## Step 1: Add `ThemeVariant` enum to `PreferencesService`

**File:** `lib/services/preferences_service.dart`

- Add a `ThemeVariant` enum with two values: `modern` (default), `classic`
- Add `label` getter for UI display ("Modern", "Classic")
- Add persistence key `_themeVariantKey`, getter `themeVariant`, and setter `setThemeVariant()`
- Follow the same pattern as `messageDensity` and `themeMode`

---

## Step 2: Add `LatticeThemeExtension` and classic theme factory methods

**File:** `lib/theme/lattice_theme.dart`

### 2a: `LatticeThemeExtension`

Add a `ThemeExtension<LatticeThemeExtension>` class with:
- `double borderRadius` — widgets read this instead of hardcoding values (modern: existing values, classic: 0)
- `bool showAvatars` — controls avatar visibility in message bubbles (modern: true, classic: false)
- Implement `copyWith()` and `lerp()` as required by `ThemeExtension`

Attach via `ThemeData.extensions` in both `_build()` (modern) and `_buildClassic()`.

### 2b: Classic color schemes — hand-crafted `ColorScheme()`

Do **not** use `ColorScheme.fromSeed()` — it produces Material You palettes that can't achieve the terminal aesthetic. Instead, construct `ColorScheme()` directly with explicit values for every role:

**Light classic:**
- `surface`: `#F5F5F5`, `surfaceContainer`: `#E0E0E0`
- `primary`: `#2E7D32` (muted green), `onPrimary`: white
- `secondary`: `#F57F17` (amber), `tertiary`: `#00897B` (teal)
- `onSurface`: `#212121`, `onSurfaceVariant`: `#616161`
- `error`: `#C62828`

**Dark classic:**
- `surface`: `#0D1117`, `surfaceContainer`: `#1A1A2E`
- `primary`: `#00FF41` (terminal green), `onPrimary`: `#0D1117`
- `secondary`: `#FFB300` (amber), `tertiary`: `#00BFA5`
- `onSurface`: `#C9D1D9`, `onSurfaceVariant`: `#8B949E`
- `error`: `#FF6B6B`

### 2c: `classicLight()` / `classicDark()` factory methods

Each calls `_buildClassic(colorScheme, brightness)`.

### 2d: `_buildClassic()` builder

- **Border radius:** 0 on all component themes (cards, inputs, FABs, buttons, chips, dialogs, popups, snackbars)
- **Elevation/shadows:** 0 on all surfaces
- **Typography:** Set `fontFamily: 'monospace'` on `ThemeData`, plus `fontFamilyFallback: ['JetBrains Mono', 'Fira Code']` on each `TextStyle` in a dedicated `_classicTextTheme()` method
- **Padding:** Tighter `contentPadding` in `InputDecorationTheme`
- **Dividers:** Solid 1px lines (no alpha)
- **Component themes to include:**
  - `CardTheme` — shape with `BorderRadius.zero`
  - `InputDecorationTheme` — `BorderRadius.zero`, tighter padding
  - `FloatingActionButtonTheme` — `BorderRadius.zero`
  - `FilledButtonTheme`, `TextButtonTheme`, `OutlinedButtonTheme` — `BorderRadius.zero`
  - `ChipThemeData` — `BorderRadius.zero` (FilterChip in room list)
  - `DialogTheme` — `BorderRadius.zero`
  - `PopupMenuTheme` — `BorderRadius.zero`
  - `SnackBarTheme` — `BorderRadius.zero`
  - `NavigationRailTheme`, `NavigationBarTheme` — flat colors
  - `AppBarTheme` — flat, no elevation
  - `DividerTheme` — solid color, no alpha

### 2e: Modern theme extension

Update existing `_build()` to also attach `LatticeThemeExtension(borderRadius: 14, showAvatars: true)` via `ThemeData.extensions`, so all widgets can read it uniformly regardless of variant.

---

## Step 3: Wire theme variant into `main.dart`

**File:** `lib/main.dart`

- Read `prefs.themeVariant` in the `Consumer2` builder
- When variant is `classic`: use `LatticeTheme.classicLight()` / `LatticeTheme.classicDark()` (no dynamic color)
- When variant is `modern` (default): use `LatticeTheme.light(lightDynamic)` / `LatticeTheme.dark(darkDynamic)` (unchanged)

---

## Step 4: Add theme variant picker to Settings UI

**File:** `lib/screens/settings_screen.dart`

- Add a new `_SettingsTile` in the PREFERENCES card for "Theme variant" (between Theme and Notifications)
  - Icon: `Icons.palette_outlined`
  - Subtitle: `prefs.themeVariant.label`
- Add a `_showVariantPicker()` method with a `RadioGroup<ThemeVariant>` dialog, following the same pattern as `_showThemePicker()`

---

## Step 5: Update widgets to read from `LatticeThemeExtension`

### 5a: `MessageBubble` (`lib/widgets/message_bubble.dart`)

- Read `LatticeThemeExtension` from theme
- Replace hardcoded `metrics.bubbleRadius` with `ext.borderRadius.clamp(0, metrics.bubbleRadius)` (so classic gets 0, modern keeps density-based values)
- When `ext.showAvatars == false`: hide the sender `CircleAvatar` and its spacing; still show sender name text

### 5b: `_RoomTile` in RoomList (`lib/widgets/room_list.dart`)

- Read `ext.borderRadius` and use it for the `Material` and `InkWell` border radii (replacing hardcoded `14`)
- Read `ext.borderRadius` for the unread badge (replacing hardcoded `10`)
- `_SectionHeader` InkWell: use `ext.borderRadius.clamp(0, 8)`

### 5c: `_RailIcon` in SpaceRail (`lib/widgets/space_rail.dart`)

- Read `ext.borderRadius` for the `AnimatedContainer` and `InkWell` (replacing hardcoded `14`/`22`)
- Unread badge: use `ext.borderRadius.clamp(0, 8)`

### 5d: `_ComposeBar` in ChatScreen (`lib/screens/chat_screen.dart`)

- Read `ext.borderRadius` for the compose `TextField`'s `OutlineInputBorder` (replacing hardcoded `24`)

### 5e: Settings buttons (`lib/screens/settings_screen.dart`)

- Read `ext.borderRadius` for `OutlinedButton` and `FilledButton.tonal` shape overrides (replacing hardcoded `14`)

---

## Step 6: Run analysis and tests

- Run `flutter analyze` — fix any lint issues
- Run `flutter test` — fix any regressions
- **New tests to add:**
  - `ThemeVariant` persistence round-trip (default → set → get) in a preferences test
  - Smoke tests that `LatticeTheme.classicLight()` and `classicDark()` return valid `ThemeData` with the extension attached

---

## Files Changed

| File | Change |
|------|--------|
| `lib/services/preferences_service.dart` | Add `ThemeVariant` enum + persistence |
| `lib/theme/lattice_theme.dart` | Add `LatticeThemeExtension`, `classicLight()`, `classicDark()`, `_buildClassic()`, `_classicTextTheme()`. Attach extension to modern theme too. |
| `lib/main.dart` | Conditionally select theme based on variant |
| `lib/screens/settings_screen.dart` | Add variant picker tile + dialog; read `ext.borderRadius` for button shapes |
| `lib/widgets/message_bubble.dart` | Read `ext.borderRadius` for bubble shape; read `ext.showAvatars` to hide avatars |
| `lib/widgets/room_list.dart` | Read `ext.borderRadius` for room tile, badge, and section header |
| `lib/widgets/space_rail.dart` | Read `ext.borderRadius` for rail icon and badge |
| `lib/screens/chat_screen.dart` | Read `ext.borderRadius` for compose bar TextField |

## Design Decisions

1. **`ThemeExtension` for widget-level styling** — A `LatticeThemeExtension` carries `borderRadius` and `showAvatars` on the theme, so widgets read styling from one place without importing `PreferencesService` or knowing about `ThemeVariant`. This keeps the variant concern inside the theme layer.
2. **Avatar hiding in messages only** — Classic hides avatars in `MessageBubble` for the IRC feel. Room list and space rail keep avatars for usability (room identification).
3. **Hand-crafted `ColorScheme()`** — Classic uses explicit terminal-inspired colors, not `ColorScheme.fromSeed()`, since seed-based palettes can't produce the desaturated/neon terminal aesthetic.
4. **No font bundling** — Use `fontFamily: 'monospace'` as base with `fontFamilyFallback: ['JetBrains Mono', 'Fira Code']` on TextStyles. This avoids increasing app size and leverages system-installed fonts.
5. **Orthogonal to brightness** — Theme variant (modern/classic) is independent of theme mode (light/dark/system). Users pick both independently, resulting in 4 combinations.
6. **Classic skips dynamic color** — The classic theme uses its own fixed palette, so `DynamicColorBuilder` results are ignored when active.

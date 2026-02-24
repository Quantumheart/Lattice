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

## Step 2: Add classic theme factory methods to `LatticeTheme`

**File:** `lib/theme/lattice_theme.dart`

- Add `classicLight()` and `classicDark()` static methods
- Add a private `_buildClassic()` builder with these characteristics:
  - **Border radius:** 0 everywhere (cards, inputs, FABs, buttons)
  - **Elevation/shadows:** 0 on all surfaces
  - **Typography:** Monospace font family (`'JetBrains Mono', 'Fira Code', monospace`) — use `fontFamilyFallback` to leverage system-installed monospace fonts without bundling assets
  - **Colors - Light:** Gray surfaces (`#f5f5f5` background, `#e0e0e0` containers), dark text, green accent (`#00c853` or similar), amber secondary
  - **Colors - Dark:** Near-black background (`#0d1117`), dark surface containers (`#1a1a2e`), green-on-black primary (`#00ff41`), amber secondary (`#ffb300`)
  - **Padding:** Tighter `contentPadding` in input decoration, smaller card padding
  - **Dividers:** Solid 1px lines (no alpha blending)
- Keep the same `useMaterial3: true` base but override component themes for the flat/blocky look

---

## Step 3: Wire theme variant into `main.dart`

**File:** `lib/main.dart`

- Read `prefs.themeVariant` in the `Consumer2` builder
- When variant is `classic`, use `LatticeTheme.classicLight()` / `LatticeTheme.classicDark()` instead of `LatticeTheme.light(lightDynamic)` / `LatticeTheme.dark(darkDynamic)`
  - Note: classic variant uses its own fixed color scheme, so dynamic color is not passed
- When variant is `modern` (default), behavior is unchanged

---

## Step 4: Add theme variant picker to Settings UI

**File:** `lib/screens/settings_screen.dart`

- Add a new `_SettingsTile` in the PREFERENCES card for "Theme variant" (between Theme and Notifications)
  - Icon: `Icons.palette_outlined`
  - Subtitle: `prefs.themeVariant.label`
- Add a `_showVariantPicker()` method with a `RadioGroup<ThemeVariant>` dialog, following the same pattern as `_showThemePicker()`

---

## Step 5: Run analysis and tests

- Run `flutter analyze` to check for lint issues
- Run `flutter test` to ensure no regressions
- Fix any issues found

---

## Files Changed

| File | Change |
|------|--------|
| `lib/services/preferences_service.dart` | Add `ThemeVariant` enum + persistence |
| `lib/theme/lattice_theme.dart` | Add `classicLight()`, `classicDark()`, `_buildClassic()` |
| `lib/main.dart` | Conditionally select theme based on variant |
| `lib/screens/settings_screen.dart` | Add variant picker tile + dialog |

## Design Decisions

1. **No font bundling** — Use `fontFamilyFallback` with common monospace font names. This avoids increasing app size and leverages fonts already installed on user systems. JetBrains Mono and Fira Code are common developer fonts; the system monospace fallback covers all other cases.
2. **Orthogonal to brightness** — Theme variant (modern/classic) is independent of theme mode (light/dark/system). Users pick both independently, resulting in 4 combinations: modern-light, modern-dark, classic-light, classic-dark.
3. **Classic skips dynamic color** — The classic theme uses its own fixed terminal-inspired palette, so `DynamicColorBuilder` results are ignored when the classic variant is active.
4. **No widget-level changes** — The classic look is achieved entirely through `ThemeData` overrides (border radius, typography, colors). Individual widgets like `MessageBubble`, `RoomList`, and `SpaceRail` already read from the theme and will adapt automatically.

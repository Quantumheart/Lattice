import 'package:flutter/material.dart';

// ── Theme extension ─────────────────────────────────────────────

/// Custom theme properties that widgets read for variant-specific styling.
class LatticeThemeExtension extends ThemeExtension<LatticeThemeExtension> {
  const LatticeThemeExtension({
    required this.borderRadius,
    required this.showAvatars,
  });

  /// Border radius used for cards, tiles, bubbles, buttons, etc.
  final double borderRadius;

  /// Whether to show sender avatars in message bubbles.
  final bool showAvatars;

  @override
  LatticeThemeExtension copyWith({double? borderRadius, bool? showAvatars}) {
    return LatticeThemeExtension(
      borderRadius: borderRadius ?? this.borderRadius,
      showAvatars: showAvatars ?? this.showAvatars,
    );
  }

  @override
  LatticeThemeExtension lerp(covariant LatticeThemeExtension? other, double t) {
    if (other == null) return this;
    return LatticeThemeExtension(
      borderRadius: lerpDouble(borderRadius, other.borderRadius, t) ?? borderRadius,
      showAvatars: t < 0.5 ? showAvatars : other.showAvatars,
    );
  }

  static double? lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

// ── Theme factory ───────────────────────────────────────────────

/// Lattice theme: Material You-inspired with expressive typography
/// and elevation layers. Falls back to a deep violet seed color
/// when the platform does not supply a dynamic palette.
class LatticeTheme {
  LatticeTheme._();

  static const Color _seedColor = Color(0xFF6750A4);

  static const _modernExtension = LatticeThemeExtension(
    borderRadius: 14,
    showAvatars: true,
  );

  static const _classicExtension = LatticeThemeExtension(
    borderRadius: 0,
    showAvatars: false,
  );

  // ── Modern Light ────────────────────────────────────────────
  static ThemeData light([ColorScheme? dynamic]) {
    final colorScheme = dynamic ??
        ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        );

    return _build(colorScheme, Brightness.light);
  }

  // ── Modern Dark ─────────────────────────────────────────────
  static ThemeData dark([ColorScheme? dynamic]) {
    final colorScheme = dynamic ??
        ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        );

    return _build(colorScheme, Brightness.dark);
  }

  // ── Classic Light ───────────────────────────────────────────
  static ThemeData classicLight() {
    const cs = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF2E7D32),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFC8E6C9),
      onPrimaryContainer: Color(0xFF1B5E20),
      secondary: Color(0xFFF57F17),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFFFF9C4),
      onSecondaryContainer: Color(0xFFE65100),
      tertiary: Color(0xFF00897B),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFB2DFDB),
      onTertiaryContainer: Color(0xFF004D40),
      error: Color(0xFFC62828),
      onError: Colors.white,
      errorContainer: Color(0xFFFFCDD2),
      onErrorContainer: Color(0xFFB71C1C),
      surface: Color(0xFFF5F5F5),
      onSurface: Color(0xFF212121),
      onSurfaceVariant: Color(0xFF616161),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF0F0F0),
      surfaceContainer: Color(0xFFE8E8E8),
      surfaceContainerHigh: Color(0xFFE0E0E0),
      surfaceContainerHighest: Color(0xFFD6D6D6),
      outline: Color(0xFF9E9E9E),
      outlineVariant: Color(0xFFBDBDBD),
    );

    return _buildClassic(cs, Brightness.light);
  }

  // ── Classic Dark ────────────────────────────────────────────
  static ThemeData classicDark() {
    const cs = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF00FF41),
      onPrimary: Color(0xFF0D1117),
      primaryContainer: Color(0xFF1A3A1A),
      onPrimaryContainer: Color(0xFF00FF41),
      secondary: Color(0xFFFFB300),
      onSecondary: Color(0xFF0D1117),
      secondaryContainer: Color(0xFF3A2E00),
      onSecondaryContainer: Color(0xFFFFD54F),
      tertiary: Color(0xFF00BFA5),
      onTertiary: Color(0xFF0D1117),
      tertiaryContainer: Color(0xFF00332C),
      onTertiaryContainer: Color(0xFF64FFDA),
      error: Color(0xFFFF6B6B),
      onError: Color(0xFF0D1117),
      errorContainer: Color(0xFF3A1A1A),
      onErrorContainer: Color(0xFFFF6B6B),
      surface: Color(0xFF0D1117),
      onSurface: Color(0xFFC9D1D9),
      onSurfaceVariant: Color(0xFF8B949E),
      surfaceContainerLowest: Color(0xFF080C10),
      surfaceContainerLow: Color(0xFF111922),
      surfaceContainer: Color(0xFF1A1A2E),
      surfaceContainerHigh: Color(0xFF21222C),
      surfaceContainerHighest: Color(0xFF2A2B36),
      outline: Color(0xFF484F58),
      outlineVariant: Color(0xFF30363D),
    );

    return _buildClassic(cs, Brightness.dark);
  }

  // ── Modern builder ──────────────────────────────────────────
  static ThemeData _build(ColorScheme cs, Brightness brightness) {
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      brightness: brightness,
      extensions: const [_modernExtension],

      // Typography
      textTheme: _textTheme(cs),

      // App bar
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
          letterSpacing: -0.2,
        ),
      ),

      // Navigation rail (the space icon rail)
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isLight ? cs.surfaceContainerLow : cs.surfaceContainer,
        indicatorColor: cs.primaryContainer,
        selectedIconTheme: IconThemeData(color: cs.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant),
        labelType: NavigationRailLabelType.none,
      ),

      // Navigation bar (bottom bar on mobile)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // Cards
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: isLight ? cs.surfaceContainerLowest : cs.surfaceContainer,
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),

      // Floating action button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // List tiles — explicit click cursor for desktop platforms
      listTileTheme: const ListTileThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),

      // Popup menus — explicit click cursor for desktop platforms
      popupMenuTheme: const PopupMenuThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),

      // Buttons — explicit click cursor for desktop platforms
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateMouseCursor.clickable,
        ),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateMouseCursor.clickable,
        ),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateMouseCursor.clickable,
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),

      // Page transitions
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ── Classic builder ─────────────────────────────────────────
  static ThemeData _buildClassic(ColorScheme cs, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    const zero = BorderRadius.zero;
    const zeroShape = RoundedRectangleBorder(borderRadius: zero);

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      brightness: brightness,
      fontFamily: 'monospace',
      extensions: const [_classicExtension],

      // Typography
      textTheme: _classicTextTheme(cs),

      // App bar — flat, no elevation
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        titleTextStyle: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['JetBrains Mono', 'Fira Code'],
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),

      // Navigation rail
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isLight ? cs.surfaceContainerLow : cs.surfaceContainer,
        indicatorColor: cs.primaryContainer,
        indicatorShape: zeroShape,
        selectedIconTheme: IconThemeData(color: cs.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant),
        labelType: NavigationRailLabelType.none,
      ),

      // Navigation bar
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        indicatorShape: zeroShape,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // Cards — sharp corners, no elevation
      cardTheme: CardThemeData(
        elevation: 0,
        shape: zeroShape,
        color: isLight ? cs.surfaceContainerLowest : cs.surfaceContainer,
      ),

      // Input decoration — sharp corners, tighter padding
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: const OutlineInputBorder(
          borderRadius: zero,
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),

      // FAB
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        elevation: 0,
        shape: zeroShape,
      ),

      // List tiles
      listTileTheme: const ListTileThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),

      // Popup menus
      popupMenuTheme: PopupMenuThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
        shape: zeroShape,
      ),

      // Buttons — sharp corners
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateMouseCursor.clickable,
          shape: WidgetStatePropertyAll(zeroShape),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateMouseCursor.clickable,
          shape: WidgetStatePropertyAll(zeroShape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateMouseCursor.clickable,
          shape: WidgetStatePropertyAll(zeroShape),
        ),
      ),

      // Chips — sharp corners
      chipTheme: const ChipThemeData(
        shape: zeroShape,
      ),

      // Dialog — sharp corners
      dialogTheme: const DialogTheme(
        shape: zeroShape,
      ),

      // Snackbar — sharp corners
      snackBarTheme: const SnackBarThemeData(
        shape: zeroShape,
      ),

      // Divider — solid, no alpha
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // Page transitions
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ── Modern text theme ───────────────────────────────────────
  static TextTheme _textTheme(ColorScheme cs) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: cs.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: cs.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: cs.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: cs.onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: cs.onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: cs.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: cs.onSurfaceVariant,
      ),
    );
  }

  // ── Classic text theme (monospace) ──────────────────────────
  static TextTheme _classicTextTheme(ColorScheme cs) {
    const fallback = ['JetBrains Mono', 'Fira Code'];
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: fallback,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: cs.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: fallback,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: cs.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: fallback,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: fallback,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: cs.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: fallback,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: cs.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: fallback,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: cs.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: fallback,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

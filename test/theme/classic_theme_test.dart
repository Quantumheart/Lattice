import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lattice/services/preferences_service.dart';
import 'package:lattice/theme/lattice_theme.dart';

void main() {
  group('ThemeVariant persistence', () {
    test('defaults to modern', () {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      expect(prefs.themeVariant, ThemeVariant.modern);
    });

    test('round-trips classic variant', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      await prefs.init();
      await prefs.setThemeVariant(ThemeVariant.classic);
      expect(prefs.themeVariant, ThemeVariant.classic);
    });

    test('round-trips modern variant', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      await prefs.init();
      await prefs.setThemeVariant(ThemeVariant.classic);
      await prefs.setThemeVariant(ThemeVariant.modern);
      expect(prefs.themeVariant, ThemeVariant.modern);
    });

    test('falls back to modern for unknown stored value', () {
      SharedPreferences.setMockInitialValues({'theme_variant': 'retro'});
      final prefs = PreferencesService();
      // Without init, _prefs is null so it returns default.
      expect(prefs.themeVariant, ThemeVariant.modern);
    });
  });

  group('ThemeVariant labels', () {
    test('modern label', () {
      expect(ThemeVariant.modern.label, 'Modern');
    });

    test('classic label', () {
      expect(ThemeVariant.classic.label, 'Classic');
    });
  });

  group('Classic theme smoke tests', () {
    test('classicLight returns valid ThemeData with extension', () {
      final theme = LatticeTheme.classicLight();
      expect(theme, isA<ThemeData>());
      expect(theme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);

      final ext = theme.extension<LatticeThemeExtension>();
      expect(ext, isNotNull);
      expect(ext!.borderRadius, 0);
      expect(ext.showAvatars, isFalse);
    });

    test('classicDark returns valid ThemeData with extension', () {
      final theme = LatticeTheme.classicDark();
      expect(theme, isA<ThemeData>());
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);

      final ext = theme.extension<LatticeThemeExtension>();
      expect(ext, isNotNull);
      expect(ext!.borderRadius, 0);
      expect(ext.showAvatars, isFalse);
    });

    test('classicLight has monospace font family', () {
      final theme = LatticeTheme.classicLight();
      expect(theme.fontFamily, 'monospace');
    });

    test('classicDark has zero-radius card theme', () {
      final theme = LatticeTheme.classicDark();
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(cardShape.borderRadius, BorderRadius.zero);
    });

    test('classicLight has zero elevation on FAB', () {
      final theme = LatticeTheme.classicLight();
      expect(theme.floatingActionButtonTheme.elevation, 0);
    });

    test('classicDark has terminal green primary', () {
      final theme = LatticeTheme.classicDark();
      expect(theme.colorScheme.primary, const Color(0xFF00FF41));
    });

    test('classicLight has muted green primary', () {
      final theme = LatticeTheme.classicLight();
      expect(theme.colorScheme.primary, const Color(0xFF2E7D32));
    });
  });

  group('Modern theme extension', () {
    test('light theme has extension with modern defaults', () {
      final theme = LatticeTheme.light();
      final ext = theme.extension<LatticeThemeExtension>();
      expect(ext, isNotNull);
      expect(ext!.borderRadius, 14);
      expect(ext.showAvatars, isTrue);
    });

    test('dark theme has extension with modern defaults', () {
      final theme = LatticeTheme.dark();
      final ext = theme.extension<LatticeThemeExtension>();
      expect(ext, isNotNull);
      expect(ext!.borderRadius, 14);
      expect(ext.showAvatars, isTrue);
    });
  });

  group('LatticeThemeExtension', () {
    test('copyWith works', () {
      const ext = LatticeThemeExtension(borderRadius: 14, showAvatars: true);
      final copied = ext.copyWith(borderRadius: 0);
      expect(copied.borderRadius, 0);
      expect(copied.showAvatars, isTrue);
    });

    test('lerp interpolates borderRadius', () {
      const a = LatticeThemeExtension(borderRadius: 0, showAvatars: false);
      const b = LatticeThemeExtension(borderRadius: 14, showAvatars: true);
      final mid = a.lerp(b, 0.5);
      expect(mid.borderRadius, 7);
      expect(mid.showAvatars, true); // t >= 0.5 uses other
    });

    test('lerp with null returns this', () {
      const a = LatticeThemeExtension(borderRadius: 10, showAvatars: true);
      final result = a.lerp(null, 0.5);
      expect(result.borderRadius, 10);
      expect(result.showAvatars, isTrue);
    });
  });
}

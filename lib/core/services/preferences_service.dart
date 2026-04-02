import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/core/theme/custom_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls how compact or spacious message bubbles appear.
enum MessageDensity {
  compact,
  defaultDensity,
  comfortable;

  /// Human-readable label for display in the UI.
  String get label => switch (this) {
        MessageDensity.compact => 'Compact',
        MessageDensity.defaultDensity => 'Default',
        MessageDensity.comfortable => 'Comfortable',
      };
}

/// Global notification level (local-only, does not affect server push rules).
enum NotificationLevel {
  all,
  mentionsOnly,
  off;

  String get label => switch (this) {
        NotificationLevel.all => 'All messages',
        NotificationLevel.mentionsOnly => 'Mentions & keywords only',
        NotificationLevel.off => 'Off',
      };
}

/// Manages user preferences that persist across app restarts.
class PreferencesService extends ChangeNotifier {
  PreferencesService({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;
  static const _densityKey = 'message_density';
  static const _themeModeKey = 'theme_mode';
  static const _themePresetKey = 'theme_preset';

  /// Initialise the underlying [SharedPreferences] instance.
  /// Must be called (and awaited) before reading any values.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove('room_filter');
    notifyListeners();
  }

  // ── Message density ───────────────────────────────────────────

  MessageDensity get messageDensity {
    final stored = _prefs?.getString(_densityKey);
    if (stored == null) return MessageDensity.defaultDensity;
    return MessageDensity.values.firstWhere(
      (d) => d.name == stored,
      orElse: () => MessageDensity.defaultDensity,
    );
  }

  Future<void> setMessageDensity(MessageDensity density) async {
    await _prefs?.setString(_densityKey, density.name);
    debugPrint('[Lattice] Message density set to ${density.label}');
    notifyListeners();
  }

  // ── Theme mode ──────────────────────────────────────────────

  ThemeMode get themeMode {
    final stored = _prefs?.getString(_themeModeKey);
    if (stored == null) return ThemeMode.system;
    return ThemeMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  String get themeModeLabel => switch (themeMode) {
        ThemeMode.system => 'System default',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setString(_themeModeKey, mode.name);
    debugPrint('[Lattice] Theme mode set to ${mode.name}');
    notifyListeners();
  }

  // ── Theme preset ─────────────────────────────────────────

  String? get themePreset => _prefs?.getString(_themePresetKey);

  Future<void> setThemePreset(String? id) async {
    if (id == null) {
      await _prefs?.remove(_themePresetKey);
    } else {
      await _prefs?.setString(_themePresetKey, id);
    }
    debugPrint('[Lattice] Theme preset set to $id');
    notifyListeners();
  }

  // ── Custom theme ─────────────────────────────────────────

  static const _customThemeKey = 'custom_theme';
  static const _customThemeModeKey = 'custom_theme_mode';

  CustomTheme get customTheme {
    final json = _prefs?.getString(_customThemeKey);
    if (json == null) return CustomTheme.defaults;
    try {
      return CustomTheme.fromJsonString(json);
    } catch (_) {
      return CustomTheme.defaults;
    }
  }

  Future<void> setCustomTheme(CustomTheme theme) async {
    await _prefs?.setString(_customThemeKey, theme.toJsonString());
    debugPrint('[Lattice] Custom theme updated');
    notifyListeners();
  }

  ThemeMode get customThemeMode {
    final stored = _prefs?.getString(_customThemeModeKey);
    if (stored == null) return ThemeMode.dark;
    return ThemeMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => ThemeMode.dark,
    );
  }

  Future<void> setCustomThemeMode(ThemeMode mode) async {
    await _prefs?.setString(_customThemeModeKey, mode.name);
    debugPrint('[Lattice] Custom theme mode set to ${mode.name}');
    notifyListeners();
  }

  // ── Collapsed space sections ─────────────────────────────
  static const _collapsedSectionsKey = 'collapsed_space_sections';

  /// Sentinel key used for the "Unsorted" section (rooms not in any space).
  static const unsortedSectionKey = '__unsorted__';

  /// Sentinel key used for the "Direct Messages" section.
  static const dmSectionKey = '__direct_messages__';

  /// Sentinel key used for the "Pinned" section (favourited rooms).
  static const pinnedSectionKey = '__pinned__';

  Set<String> get collapsedSpaceSections {
    final list = _prefs?.getStringList(_collapsedSectionsKey);
    return list != null ? Set<String>.from(list) : {};
  }

  Future<void> toggleSectionCollapsed(String spaceId) async {
    final current = collapsedSpaceSections;
    if (current.contains(spaceId)) {
      current.remove(spaceId);
    } else {
      current.add(spaceId);
    }
    await _prefs?.setStringList(_collapsedSectionsKey, current.toList());
    notifyListeners();
  }

  // ── Space ordering ─────────────────────────────────────────
  static const _spaceOrderKey = 'space_order';

  List<String> get spaceOrder =>
      _prefs?.getStringList(_spaceOrderKey) ?? [];

  Future<void> setSpaceOrder(List<String> order) async {
    await _prefs?.setStringList(_spaceOrderKey, order);
    notifyListeners();
  }

  // ── Room list panel width ─────────────────────────────────

  static const _panelWidthKey = 'room_list_panel_width';
  static const double defaultPanelWidth = 360;
  static const double collapsedPanelWidth = 0;
  static const double collapseThreshold = 240;
  static const double maxPanelWidth = 500;

  double get panelWidth {
    return _prefs?.getDouble(_panelWidthKey) ?? defaultPanelWidth;
  }

  Future<void> setPanelWidth(double width) async {
    final clamped = width.clamp(collapsedPanelWidth, maxPanelWidth);
    await _prefs?.setDouble(_panelWidthKey, clamped);
    notifyListeners();
  }

  // ── Notification level ──────────────────────────────────────

  static const _notificationLevelKey = 'notification_level';

  NotificationLevel get notificationLevel {
    final stored = _prefs?.getString(_notificationLevelKey);
    if (stored == null) return NotificationLevel.all;
    return NotificationLevel.values.firstWhere(
      (l) => l.name == stored,
      orElse: () => NotificationLevel.all,
    );
  }

  String get notificationLevelLabel => notificationLevel.label;

  Future<void> setNotificationLevel(NotificationLevel level) async {
    await _prefs?.setString(_notificationLevelKey, level.name);
    debugPrint('[Lattice] Notification level set to ${level.label}');
    notifyListeners();
  }

  // ── Notification keywords ───────────────────────────────────

  static const _notificationKeywordsKey = 'notification_keywords';

  List<String> get notificationKeywords =>
      _prefs?.getStringList(_notificationKeywordsKey) ?? [];

  Future<void> setNotificationKeywords(List<String> keywords) async {
    await _prefs?.setStringList(_notificationKeywordsKey, keywords);
    debugPrint('[Lattice] Notification keywords updated: $keywords');
    notifyListeners();
  }

  Future<void> addNotificationKeyword(String keyword) async {
    final trimmed = keyword.trim().toLowerCase();
    if (trimmed.isEmpty) return;
    final current = notificationKeywords;
    if (current.contains(trimmed)) return;
    current.add(trimmed);
    await setNotificationKeywords(current);
  }

  Future<void> removeNotificationKeyword(String keyword) async {
    final current = notificationKeywords;
    current.remove(keyword);
    await setNotificationKeywords(current);
  }

  // ── Link previews ─────────────────────────────────────────────

  static const _showLinkPreviewsKey = 'show_link_previews';

  bool get showLinkPreviews =>
      _prefs?.getBool(_showLinkPreviewsKey) ?? true;

  Future<void> setShowLinkPreviews(bool value) async {
    await _prefs?.setBool(_showLinkPreviewsKey, value);
    debugPrint(
        '[Lattice] Link previews ${value ? "enabled" : "disabled"}',);
    notifyListeners();
  }

  // ── Typing indicators ─────────────────────────────────────────

  static const _typingIndicatorsKey = 'typing_indicators';

  bool get typingIndicators =>
      _prefs?.getBool(_typingIndicatorsKey) ?? true;

  Future<void> setTypingIndicators(bool value) async {
    await _prefs?.setBool(_typingIndicatorsKey, value);
    debugPrint(
        '[Lattice] Typing indicators ${value ? "enabled" : "disabled"}',);
    notifyListeners();
  }

  // ── Read receipts ───────────────────────────────────────────────

  static const _readReceiptsKey = 'read_receipts';

  bool get readReceipts => _prefs?.getBool(_readReceiptsKey) ?? true;

  Future<void> setReadReceipts(bool value) async {
    await _prefs?.setBool(_readReceiptsKey, value);
    debugPrint(
        '[Lattice] Read receipts ${value ? "enabled" : "disabled"}',);
    notifyListeners();
  }

  // ── OS notification toggles ──────────────────────────────────

  static const _osNotificationsEnabledKey = 'os_notifications_enabled';
  static const _notificationSoundEnabledKey = 'notification_sound_enabled';
  static const _notificationVibrationEnabledKey =
      'notification_vibration_enabled';
  static const _foregroundNotificationsEnabledKey =
      'foreground_notifications_enabled';

  bool get osNotificationsEnabled =>
      _prefs?.getBool(_osNotificationsEnabledKey) ?? true;

  Future<void> setOsNotificationsEnabled(bool value) async {
    await _prefs?.setBool(_osNotificationsEnabledKey, value);
    debugPrint('[Lattice] OS notifications ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }

  bool get notificationSoundEnabled =>
      _prefs?.getBool(_notificationSoundEnabledKey) ?? true;

  Future<void> setNotificationSoundEnabled(bool value) async {
    await _prefs?.setBool(_notificationSoundEnabledKey, value);
    debugPrint(
        '[Lattice] Notification sound ${value ? "enabled" : "disabled"}',);
    notifyListeners();
  }

  bool get notificationVibrationEnabled =>
      _prefs?.getBool(_notificationVibrationEnabledKey) ?? true;

  Future<void> setNotificationVibrationEnabled(bool value) async {
    await _prefs?.setBool(_notificationVibrationEnabledKey, value);
    debugPrint(
        '[Lattice] Notification vibration ${value ? "enabled" : "disabled"}',);
    notifyListeners();
  }

  bool get foregroundNotificationsEnabled =>
      _prefs?.getBool(_foregroundNotificationsEnabledKey) ?? false;

  Future<void> setForegroundNotificationsEnabled(bool value) async {
    await _prefs?.setBool(_foregroundNotificationsEnabledKey, value);
    debugPrint(
        '[Lattice] Foreground notifications ${value ? "enabled" : "disabled"}',);
    notifyListeners();
  }

  // ── Push notifications ─────────────────────────────────────────

  static const _pushEnabledKey = 'push_enabled';
  static const _pushDistributorKey = 'push_distributor';

  bool get pushEnabled => _prefs?.getBool(_pushEnabledKey) ?? false;

  Future<void> setPushEnabled(bool value) async {
    await _prefs?.setBool(_pushEnabledKey, value);
    debugPrint('[Lattice] Push notifications ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }

  String? get pushDistributor => _prefs?.getString(_pushDistributorKey);

  Future<void> setPushDistributor(String? distributor) async {
    if (distributor == null) {
      await _prefs?.remove(_pushDistributorKey);
    } else {
      await _prefs?.setString(_pushDistributorKey, distributor);
    }
    debugPrint('[Lattice] Push distributor set to $distributor');
    notifyListeners();
  }
}

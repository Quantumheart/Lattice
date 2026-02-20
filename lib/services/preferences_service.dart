import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which subset of rooms to show in the room list.
enum RoomFilter {
  all,
  directMessages,
  groups,
  unread,
  favourites;

  String get label => switch (this) {
        RoomFilter.all => 'All',
        RoomFilter.directMessages => 'DMs',
        RoomFilter.groups => 'Groups',
        RoomFilter.unread => 'Unread',
        RoomFilter.favourites => 'Favourites',
      };

  IconData get icon => switch (this) {
        RoomFilter.all => Icons.chat_bubble_outline_rounded,
        RoomFilter.directMessages => Icons.person_outline_rounded,
        RoomFilter.groups => Icons.group_outlined,
        RoomFilter.unread => Icons.mark_chat_unread_outlined,
        RoomFilter.favourites => Icons.star_outline_rounded,
      };
}

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

/// Manages user preferences that persist across app restarts.
class PreferencesService extends ChangeNotifier {
  PreferencesService({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;
  static const _densityKey = 'message_density';
  static const _themeModeKey = 'theme_mode';

  /// Initialise the underlying [SharedPreferences] instance.
  /// Must be called (and awaited) before reading any values.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
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

  // ── Room filter ─────────────────────────────────────────────

  static const _roomFilterKey = 'room_filter';

  RoomFilter get roomFilter {
    final stored = _prefs?.getString(_roomFilterKey);
    if (stored == null) return RoomFilter.all;
    return RoomFilter.values.firstWhere(
      (f) => f.name == stored,
      orElse: () => RoomFilter.all,
    );
  }

  Future<void> setRoomFilter(RoomFilter filter) async {
    await _prefs?.setString(_roomFilterKey, filter.name);
    debugPrint('[Lattice] Room filter set to ${filter.label}');
    notifyListeners();
  }

  // ── Room list panel width ─────────────────────────────────

  static const _panelWidthKey = 'room_list_panel_width';
  static const double defaultPanelWidth = 360;
  static const double minPanelWidth = 0;
  static const double maxPanelWidth = 500;

  double get panelWidth {
    return _prefs?.getDouble(_panelWidthKey) ?? defaultPanelWidth;
  }

  Future<void> setPanelWidth(double width) async {
    final clamped = width.clamp(minPanelWidth, maxPanelWidth);
    await _prefs?.setDouble(_panelWidthKey, clamped);
    notifyListeners();
  }
}

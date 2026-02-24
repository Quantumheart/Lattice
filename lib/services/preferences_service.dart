import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which subset of rooms to show in the room list.
enum RoomCategory {
  all,
  directMessages,
  groups,
  unread,
  favourites;

  String get label => switch (this) {
        RoomCategory.all => 'All',
        RoomCategory.directMessages => 'DMs',
        RoomCategory.groups => 'Groups',
        RoomCategory.unread => 'Unread',
        RoomCategory.favourites => 'Favourites',
      };

  IconData get icon => switch (this) {
        RoomCategory.all => Icons.chat_bubble_outline_rounded,
        RoomCategory.directMessages => Icons.person_outline_rounded,
        RoomCategory.groups => Icons.group_outlined,
        RoomCategory.unread => Icons.mark_chat_unread_outlined,
        RoomCategory.favourites => Icons.star_outline_rounded,
      };
}

/// Visual theme variant — modern (Material You) or classic (IRC/terminal).
enum ThemeVariant {
  modern,
  classic;

  String get label => switch (this) {
        ThemeVariant.modern => 'Modern',
        ThemeVariant.classic => 'Classic',
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
  static const _themeVariantKey = 'theme_variant';

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

  // ── Theme variant ──────────────────────────────────────────

  ThemeVariant get themeVariant {
    final stored = _prefs?.getString(_themeVariantKey);
    if (stored == null) return ThemeVariant.modern;
    return ThemeVariant.values.firstWhere(
      (v) => v.name == stored,
      orElse: () => ThemeVariant.modern,
    );
  }

  Future<void> setThemeVariant(ThemeVariant variant) async {
    await _prefs?.setString(_themeVariantKey, variant.name);
    debugPrint('[Lattice] Theme variant set to ${variant.label}');
    notifyListeners();
  }

  // ── Room filter ─────────────────────────────────────────────

  static const _roomFilterKey = 'room_filter';

  RoomCategory get roomFilter {
    final stored = _prefs?.getString(_roomFilterKey);
    if (stored == null) return RoomCategory.all;
    return RoomCategory.values.firstWhere(
      (f) => f.name == stored,
      orElse: () => RoomCategory.all,
    );
  }

  Future<void> setRoomCategory(RoomCategory filter) async {
    await _prefs?.setString(_roomFilterKey, filter.name);
    debugPrint('[Lattice] Room filter set to ${filter.label}');
    notifyListeners();
  }

  // ── Collapsed space sections ─────────────────────────────
  static const _collapsedSectionsKey = 'collapsed_space_sections';

  /// Sentinel key used for the "Unsorted" section (rooms not in any space).
  static const unsortedSectionKey = '__unsorted__';

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
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

enum AudioQuality {
  speech,
  music,
  high;

  String get label => switch (this) {
        AudioQuality.speech => 'Speech (24 kbps)',
        AudioQuality.music => 'Standard (48 kbps)',
        AudioQuality.high => 'High quality (96 kbps)',
      };
}

/// Manages user preferences that persist across app restarts.
class PreferencesService extends ChangeNotifier {
  PreferencesService({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;
  static const _defaultHomeserverKey = 'default_homeserver';
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

  // ── Default homeserver ────────────────────────────────────────

  String? get defaultHomeserver => _prefs?.getString(_defaultHomeserverKey);

  Future<void> setDefaultHomeserver(String? server) async {
    if (server == null) {
      await _prefs?.remove(_defaultHomeserverKey);
    } else {
      await _prefs?.setString(_defaultHomeserverKey, server);
    }
    debugPrint('[Lattice] Default homeserver set to $server');
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

  String get themeModeLabel => 'Change your appearance settings';

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

  List<String> get spaceOrder => _prefs?.getStringList(_spaceOrderKey) ?? [];

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

  bool get showLinkPreviews => _prefs?.getBool(_showLinkPreviewsKey) ?? true;

  Future<void> setShowLinkPreviews(bool value) async {
    await _prefs?.setBool(_showLinkPreviewsKey, value);
    debugPrint(
      '[Lattice] Link previews ${value ? "enabled" : "disabled"}',
    );
    notifyListeners();
  }

  // ── Typing indicators ─────────────────────────────────────────

  static const _typingIndicatorsKey = 'typing_indicators';

  bool get typingIndicators => _prefs?.getBool(_typingIndicatorsKey) ?? true;

  Future<void> setTypingIndicators(bool value) async {
    await _prefs?.setBool(_typingIndicatorsKey, value);
    debugPrint(
      '[Lattice] Typing indicators ${value ? "enabled" : "disabled"}',
    );
    notifyListeners();
  }

  // ── Read receipts ───────────────────────────────────────────────

  static const _readReceiptsKey = 'read_receipts';

  bool get readReceipts => _prefs?.getBool(_readReceiptsKey) ?? true;

  Future<void> setReadReceipts(bool value) async {
    await _prefs?.setBool(_readReceiptsKey, value);
    debugPrint(
      '[Lattice] Read receipts ${value ? "enabled" : "disabled"}',
    );
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
      _prefs?.getBool(_osNotificationsEnabledKey) ?? !kIsWeb;

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
      '[Lattice] Notification sound ${value ? "enabled" : "disabled"}',
    );
    notifyListeners();
  }

  bool get notificationVibrationEnabled =>
      _prefs?.getBool(_notificationVibrationEnabledKey) ?? true;

  Future<void> setNotificationVibrationEnabled(bool value) async {
    await _prefs?.setBool(_notificationVibrationEnabledKey, value);
    debugPrint(
      '[Lattice] Notification vibration ${value ? "enabled" : "disabled"}',
    );
    notifyListeners();
  }

  bool get foregroundNotificationsEnabled =>
      _prefs?.getBool(_foregroundNotificationsEnabledKey) ?? false;

  Future<void> setForegroundNotificationsEnabled(bool value) async {
    await _prefs?.setBool(_foregroundNotificationsEnabledKey, value);
    debugPrint(
      '[Lattice] Foreground notifications ${value ? "enabled" : "disabled"}',
    );
    notifyListeners();
  }

  // ── Push notifications ─────────────────────────────────────────

  static const _pushEnabledKey = 'push_enabled';
  static const _pushDistributorKey = 'push_distributor';

  bool get pushEnabled => _prefs?.getBool(_pushEnabledKey) ?? false;

  Future<void> setPushEnabled(bool value) async {
    await _prefs?.setBool(_pushEnabledKey, value);
    debugPrint(
        '[Lattice] Push notifications ${value ? "enabled" : "disabled"}',);
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

  // ── Web push notifications ────────────────────────────────────

  static const _webPushEnabledKey = 'web_push_enabled';

  bool get webPushEnabled => _prefs?.getBool(_webPushEnabledKey) ?? false;

  Future<void> setWebPushEnabled(bool value) async {
    await _prefs?.setBool(_webPushEnabledKey, value);
    debugPrint(
      '[Lattice] Web push notifications ${value ? "enabled" : "disabled"}',
    );
    notifyListeners();
  }

  // ── Voice & video ─────────────────────────────────────────────

  static const _autoMuteOnJoinKey = 'auto_mute_on_join';
  static const _noiseSuppressionKey = 'noise_suppression';
  static const _echoCancellationKey = 'echo_cancellation';
  static const _pushToTalkEnabledKey = 'push_to_talk_enabled';
  static const _pushToTalkKeyIdKey = 'push_to_talk_key_id';
  static const _inputDeviceIdKey = 'input_device_id';
  static const _outputDeviceIdKey = 'output_device_id';
  static const _inputVolumeKey = 'input_volume';
  static const _outputVolumeKey = 'output_volume';

  bool get autoMuteOnJoin => _prefs?.getBool(_autoMuteOnJoinKey) ?? false;

  Future<void> setAutoMuteOnJoin(bool value) async {
    await _prefs?.setBool(_autoMuteOnJoinKey, value);
    debugPrint('[Lattice] Auto-mute on join ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }

  bool get noiseSuppression => _prefs?.getBool(_noiseSuppressionKey) ?? true;

  Future<void> setNoiseSuppression(bool value) async {
    await _prefs?.setBool(_noiseSuppressionKey, value);
    debugPrint('[Lattice] Noise suppression ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }

  bool get echoCancellation => _prefs?.getBool(_echoCancellationKey) ?? true;

  Future<void> setEchoCancellation(bool value) async {
    await _prefs?.setBool(_echoCancellationKey, value);
    debugPrint('[Lattice] Echo cancellation ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }

  bool get pushToTalkEnabled =>
      _prefs?.getBool(_pushToTalkEnabledKey) ?? false;

  Future<void> setPushToTalkEnabled(bool value) async {
    await _prefs?.setBool(_pushToTalkEnabledKey, value);
    debugPrint('[Lattice] Push-to-talk ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }

  int get pushToTalkKeyId =>
      _prefs?.getInt(_pushToTalkKeyIdKey) ??
      LogicalKeyboardKey.controlLeft.keyId;

  Future<void> setPushToTalkKeyId(int keyId) async {
    await _prefs?.setInt(_pushToTalkKeyIdKey, keyId);
    debugPrint('[Lattice] Push-to-talk key set to $keyId');
    notifyListeners();
  }

  String? get inputDeviceId => _prefs?.getString(_inputDeviceIdKey);

  Future<void> setInputDeviceId(String? deviceId) async {
    if (deviceId == null) {
      await _prefs?.remove(_inputDeviceIdKey);
    } else {
      await _prefs?.setString(_inputDeviceIdKey, deviceId);
    }
    debugPrint('[Lattice] Input device set to $deviceId');
    notifyListeners();
  }

  String? get outputDeviceId => _prefs?.getString(_outputDeviceIdKey);

  Future<void> setOutputDeviceId(String? deviceId) async {
    if (deviceId == null) {
      await _prefs?.remove(_outputDeviceIdKey);
    } else {
      await _prefs?.setString(_outputDeviceIdKey, deviceId);
    }
    debugPrint('[Lattice] Output device set to $deviceId');
    notifyListeners();
  }

  double get inputVolume => _prefs?.getDouble(_inputVolumeKey) ?? 1.0;

  Future<void> setInputVolume(double value) async {
    await _prefs?.setDouble(_inputVolumeKey, value.clamp(0.0, 1.0));
    debugPrint('[Lattice] Input volume set to $value');
    notifyListeners();
  }

  double get outputVolume => _prefs?.getDouble(_outputVolumeKey) ?? 1.0;

  Future<void> setOutputVolume(double value) async {
    await _prefs?.setDouble(_outputVolumeKey, value.clamp(0.0, 1.0));
    debugPrint('[Lattice] Output volume set to $value');
    notifyListeners();
  }

  static const _autoGainControlKey = 'auto_gain_control';
  static const _voiceIsolationKey = 'voice_isolation';
  static const _typingNoiseDetectionKey = 'typing_noise_detection';
  static const _audioQualityKey = 'audio_quality';

  bool get autoGainControl => _prefs?.getBool(_autoGainControlKey) ?? true;

  Future<void> setAutoGainControl(bool value) async {
    await _prefs?.setBool(_autoGainControlKey, value);
    debugPrint('[Lattice] Auto gain control ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }

  bool get voiceIsolation => _prefs?.getBool(_voiceIsolationKey) ?? true;

  Future<void> setVoiceIsolation(bool value) async {
    await _prefs?.setBool(_voiceIsolationKey, value);
    debugPrint('[Lattice] Voice isolation ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }

  bool get typingNoiseDetection =>
      _prefs?.getBool(_typingNoiseDetectionKey) ?? true;

  Future<void> setTypingNoiseDetection(bool value) async {
    await _prefs?.setBool(_typingNoiseDetectionKey, value);
    debugPrint(
      '[Lattice] Typing noise detection ${value ? "enabled" : "disabled"}',
    );
    notifyListeners();
  }

  AudioQuality get audioQuality {
    final stored = _prefs?.getString(_audioQualityKey);
    if (stored == null) return AudioQuality.music;
    return AudioQuality.values.firstWhere(
      (q) => q.name == stored,
      orElse: () => AudioQuality.music,
    );
  }

  Future<void> setAudioQuality(AudioQuality quality) async {
    await _prefs?.setString(_audioQualityKey, quality.name);
    debugPrint('[Lattice] Audio quality set to ${quality.label}');
    notifyListeners();
  }

  static const _highPassFilterKey = 'high_pass_filter';
  static const _pttSoundEnabledKey = 'ptt_sound_enabled';

  bool get highPassFilter => _prefs?.getBool(_highPassFilterKey) ?? false;

  Future<void> setHighPassFilter(bool value) async {
    await _prefs?.setBool(_highPassFilterKey, value);
    debugPrint('[Lattice] High pass filter ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }

  bool get pttSoundEnabled => _prefs?.getBool(_pttSoundEnabledKey) ?? true;

  Future<void> setPttSoundEnabled(bool value) async {
    await _prefs?.setBool(_pttSoundEnabledKey, value);
    debugPrint('[Lattice] PTT sound ${value ? "enabled" : "disabled"}');
    notifyListeners();
  }
}

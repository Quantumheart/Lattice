import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);
  });

  group('notification level', () {
    test('defaults to all', () {
      expect(prefs.notificationLevel, NotificationLevel.all);
    });

    test('label defaults to All messages', () {
      expect(prefs.notificationLevelLabel, 'All messages');
    });

    test('round-trips mentionsOnly', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(prefs.notificationLevel, NotificationLevel.mentionsOnly);
      expect(prefs.notificationLevelLabel, 'Mentions & keywords only');
    });

    test('round-trips off', () async {
      await prefs.setNotificationLevel(NotificationLevel.off);
      expect(prefs.notificationLevel, NotificationLevel.off);
      expect(prefs.notificationLevelLabel, 'Off');
    });

    test('notifies listeners on change', () async {
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setNotificationLevel(NotificationLevel.off);
      expect(notified, isTrue);
    });
  });

  group('notification keywords', () {
    test('defaults to empty list', () {
      expect(prefs.notificationKeywords, isEmpty);
    });

    test('add keyword persists', () async {
      await prefs.addNotificationKeyword('hello');
      expect(prefs.notificationKeywords, ['hello']);
    });

    test('add keyword trims whitespace', () async {
      await prefs.addNotificationKeyword('  world  ');
      expect(prefs.notificationKeywords, ['world']);
    });

    test('add keyword deduplicates', () async {
      await prefs.addNotificationKeyword('hello');
      await prefs.addNotificationKeyword('hello');
      expect(prefs.notificationKeywords, ['hello']);
    });

    test('add keyword deduplicates case-insensitively', () async {
      await prefs.addNotificationKeyword('Hello');
      await prefs.addNotificationKeyword('HELLO');
      expect(prefs.notificationKeywords, ['hello']);
    });

    test('add keyword normalizes to lowercase', () async {
      await prefs.addNotificationKeyword('FooBar');
      expect(prefs.notificationKeywords, ['foobar']);
    });

    test('add empty keyword is ignored', () async {
      await prefs.addNotificationKeyword('  ');
      expect(prefs.notificationKeywords, isEmpty);
    });

    test('remove keyword works', () async {
      await prefs.addNotificationKeyword('hello');
      await prefs.addNotificationKeyword('world');
      await prefs.removeNotificationKeyword('hello');
      expect(prefs.notificationKeywords, ['world']);
    });

    test('notifies listeners on add', () async {
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.addNotificationKeyword('test');
      expect(notified, isTrue);
    });
  });

  group('typing indicators', () {
    test('typingIndicators defaults to true', () {
      expect(prefs.typingIndicators, isTrue);
    });

    test('typingIndicators round-trips false', () async {
      await prefs.setTypingIndicators(false);
      expect(prefs.typingIndicators, isFalse);
    });

    test('typingIndicators notifies listeners', () async {
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setTypingIndicators(false);
      expect(notified, isTrue);
    });
  });

  group('read receipts', () {
    test('readReceipts defaults to true', () {
      expect(prefs.readReceipts, isTrue);
    });

    test('readReceipts round-trips false', () async {
      await prefs.setReadReceipts(false);
      expect(prefs.readReceipts, isFalse);
    });

    test('readReceipts notifies listeners', () async {
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setReadReceipts(false);
      expect(notified, isTrue);
    });
  });

  group('theme preset', () {
    test('defaults to null', () {
      expect(prefs.themePreset, isNull);
    });

    test('round-trips a preset id', () async {
      await prefs.setThemePreset('ocean');
      expect(prefs.themePreset, 'ocean');
    });

    test('clears to null', () async {
      await prefs.setThemePreset('ocean');
      await prefs.setThemePreset(null);
      expect(prefs.themePreset, isNull);
    });

    test('notifies listeners on change', () async {
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setThemePreset('purple');
      expect(notified, isTrue);
    });
  });

  group('default homeserver', () {
    test('defaults to null', () {
      expect(prefs.defaultHomeserver, isNull);
    });

    test('round-trips a server', () async {
      await prefs.setDefaultHomeserver('example.com');
      expect(prefs.defaultHomeserver, 'example.com');
    });

    test('clears to null', () async {
      await prefs.setDefaultHomeserver('example.com');
      await prefs.setDefaultHomeserver(null);
      expect(prefs.defaultHomeserver, isNull);
    });

    test('notifies listeners on change', () async {
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setDefaultHomeserver('example.com');
      expect(notified, isTrue);
    });
  });

  group('OS notification toggles', () {
    test('osNotificationsEnabled defaults to true', () {
      expect(prefs.osNotificationsEnabled, isTrue);
    });

    test('osNotificationsEnabled round-trips false', () async {
      await prefs.setOsNotificationsEnabled(false);
      expect(prefs.osNotificationsEnabled, isFalse);
    });

    test('osNotificationsEnabled notifies listeners', () async {
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setOsNotificationsEnabled(false);
      expect(notified, isTrue);
    });

    test('notificationSoundEnabled defaults to true', () {
      expect(prefs.notificationSoundEnabled, isTrue);
    });

    test('notificationSoundEnabled round-trips false', () async {
      await prefs.setNotificationSoundEnabled(false);
      expect(prefs.notificationSoundEnabled, isFalse);
    });

    test('notificationVibrationEnabled defaults to true', () {
      expect(prefs.notificationVibrationEnabled, isTrue);
    });

    test('notificationVibrationEnabled round-trips false', () async {
      await prefs.setNotificationVibrationEnabled(false);
      expect(prefs.notificationVibrationEnabled, isFalse);
    });

    test('foregroundNotificationsEnabled defaults to false', () {
      expect(prefs.foregroundNotificationsEnabled, isFalse);
    });

    test('foregroundNotificationsEnabled round-trips true', () async {
      await prefs.setForegroundNotificationsEnabled(true);
      expect(prefs.foregroundNotificationsEnabled, isTrue);
    });

    test('foregroundNotificationsEnabled notifies listeners', () async {
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setForegroundNotificationsEnabled(true);
      expect(notified, isTrue);
    });
  });

  group('voice & video settings', () {
    test('autoMuteOnJoin defaults to false', () {
      expect(prefs.autoMuteOnJoin, isFalse);
    });

    test('noiseSuppression defaults to true', () {
      expect(prefs.noiseSuppression, isTrue);
    });

    test('echoCancellation defaults to true', () {
      expect(prefs.echoCancellation, isTrue);
    });

    test('pushToTalkEnabled defaults to false', () {
      expect(prefs.pushToTalkEnabled, isFalse);
    });

    test('inputDeviceId defaults to null', () {
      expect(prefs.inputDeviceId, isNull);
    });

    test('outputDeviceId defaults to null', () {
      expect(prefs.outputDeviceId, isNull);
    });

    test('inputVolume defaults to 1.0', () {
      expect(prefs.inputVolume, 1.0);
    });

    test('outputVolume defaults to 1.0', () {
      expect(prefs.outputVolume, 1.0);
    });

    test('round-trips autoMuteOnJoin', () async {
      await prefs.setAutoMuteOnJoin(true);
      expect(prefs.autoMuteOnJoin, isTrue);
    });

    test('round-trips noiseSuppression', () async {
      await prefs.setNoiseSuppression(false);
      expect(prefs.noiseSuppression, isFalse);
    });

    test('round-trips echoCancellation', () async {
      await prefs.setEchoCancellation(false);
      expect(prefs.echoCancellation, isFalse);
    });

    test('round-trips pushToTalkEnabled', () async {
      await prefs.setPushToTalkEnabled(true);
      expect(prefs.pushToTalkEnabled, isTrue);
    });

    test('round-trips pushToTalkKeyId', () async {
      await prefs.setPushToTalkKeyId(42);
      expect(prefs.pushToTalkKeyId, 42);
    });

    test('round-trips inputDeviceId', () async {
      await prefs.setInputDeviceId('mic-1');
      expect(prefs.inputDeviceId, 'mic-1');
    });

    test('round-trips outputDeviceId', () async {
      await prefs.setOutputDeviceId('speaker-1');
      expect(prefs.outputDeviceId, 'speaker-1');
    });

    test('clears inputDeviceId with null', () async {
      await prefs.setInputDeviceId('mic-1');
      await prefs.setInputDeviceId(null);
      expect(prefs.inputDeviceId, isNull);
    });

    test('clears outputDeviceId with null', () async {
      await prefs.setOutputDeviceId('speaker-1');
      await prefs.setOutputDeviceId(null);
      expect(prefs.outputDeviceId, isNull);
    });

    test('round-trips inputVolume', () async {
      await prefs.setInputVolume(0.5);
      expect(prefs.inputVolume, 0.5);
    });

    test('round-trips outputVolume', () async {
      await prefs.setOutputVolume(0.75);
      expect(prefs.outputVolume, 0.75);
    });

    test('clamps inputVolume to 0-1 range', () async {
      await prefs.setInputVolume(1.5);
      expect(prefs.inputVolume, 1.0);
      await prefs.setInputVolume(-0.5);
      expect(prefs.inputVolume, 0.0);
    });

    test('notifies listeners on voice setting changes', () async {
      var count = 0;
      prefs.addListener(() => count++);

      await prefs.setAutoMuteOnJoin(true);
      await prefs.setNoiseSuppression(false);
      await prefs.setEchoCancellation(false);
      await prefs.setPushToTalkEnabled(true);
      await prefs.setPushToTalkKeyId(99);
      await prefs.setInputDeviceId('mic-1');
      await prefs.setOutputDeviceId('speaker-1');
      await prefs.setInputVolume(0.5);
      await prefs.setOutputVolume(0.75);
      await prefs.setAutoGainControl(false);
      await prefs.setVoiceIsolation(false);
      await prefs.setTypingNoiseDetection(false);
      await prefs.setAudioQuality(AudioQuality.high);

      expect(count, 13);
    });

    test('autoGainControl defaults to true', () {
      expect(prefs.autoGainControl, isTrue);
    });

    test('voiceIsolation defaults to true', () {
      expect(prefs.voiceIsolation, isTrue);
    });

    test('typingNoiseDetection defaults to true', () {
      expect(prefs.typingNoiseDetection, isTrue);
    });

    test('audioQuality defaults to music', () {
      expect(prefs.audioQuality, AudioQuality.music);
    });

    test('round-trips autoGainControl', () async {
      await prefs.setAutoGainControl(false);
      expect(prefs.autoGainControl, isFalse);
    });

    test('round-trips voiceIsolation', () async {
      await prefs.setVoiceIsolation(false);
      expect(prefs.voiceIsolation, isFalse);
    });

    test('round-trips typingNoiseDetection', () async {
      await prefs.setTypingNoiseDetection(false);
      expect(prefs.typingNoiseDetection, isFalse);
    });

    test('round-trips audioQuality', () async {
      await prefs.setAudioQuality(AudioQuality.high);
      expect(prefs.audioQuality, AudioQuality.high);
      await prefs.setAudioQuality(AudioQuality.speech);
      expect(prefs.audioQuality, AudioQuality.speech);
    });

    test('highPassFilter defaults to false', () {
      expect(prefs.highPassFilter, isFalse);
    });

    test('round-trips highPassFilter', () async {
      await prefs.setHighPassFilter(true);
      expect(prefs.highPassFilter, isTrue);
    });

    test('pttSoundEnabled defaults to true', () {
      expect(prefs.pttSoundEnabled, isTrue);
    });

    test('round-trips pttSoundEnabled', () async {
      await prefs.setPttSoundEnabled(false);
      expect(prefs.pttSoundEnabled, isFalse);
    });
  });
}

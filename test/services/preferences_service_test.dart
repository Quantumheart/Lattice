import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lattice/services/preferences_service.dart';

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
}

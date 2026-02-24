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
}

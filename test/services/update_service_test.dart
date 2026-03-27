import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _releaseJson({
  String tagName = 'v2.0.0',
  String htmlUrl = 'https://github.com/Quantumheart/Lattice/releases/tag/v2.0.0',
  bool draft = false,
  bool prerelease = false,
}) {
  return jsonEncode({
    'tag_name': tagName,
    'html_url': htmlUrl,
    'draft': draft,
    'prerelease': prerelease,
  });
}

Future<UpdateService> _createService({
  required http.Client client,
  String currentVersion = '1.0.0',
  Map<String, Object>? prefsValues,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues ?? {});
  final sp = await SharedPreferences.getInstance();
  final prefs = PreferencesService(prefs: sp);
  final service = UpdateService(prefs: prefs, httpClient: client);
  service.currentVersion = currentVersion;
  return service;
}

void main() {
  // ── Version comparison ──────────────────────────────────────

  group('isNewer', () {
    test('newer major version', () {
      expect(UpdateService.isNewer('2.0.0', '1.0.0'), isTrue);
    });

    test('newer minor version', () {
      expect(UpdateService.isNewer('1.1.0', '1.0.0'), isTrue);
    });

    test('newer patch version', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
    });

    test('same version is not newer', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
    });

    test('older version is not newer', () {
      expect(UpdateService.isNewer('1.0.0', '2.0.0'), isFalse);
    });

    test('older minor is not newer', () {
      expect(UpdateService.isNewer('1.0.0', '1.1.0'), isFalse);
    });

    test('mismatched segment count — latest has more', () {
      expect(UpdateService.isNewer('1.0.1', '1.0'), isTrue);
    });

    test('mismatched segment count — current has more', () {
      expect(UpdateService.isNewer('1.0', '1.0.1'), isFalse);
    });

    test('equal with different segment count', () {
      expect(UpdateService.isNewer('1.0', '1.0.0'), isFalse);
    });

    test('large version numbers', () {
      expect(UpdateService.isNewer('10.20.30', '10.20.29'), isTrue);
    });
  });

  // ── checkForUpdate ──────────────────────────────────────────

  group('checkForUpdate', () {
    test('sets updateAvailable when newer release exists', () async {
      final client = MockClient(
        (_) async => http.Response(_releaseJson(), 200),
      );
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.updateAvailable);
      expect(service.latestVersion, '2.0.0');
      expect(service.releaseUrl, contains('v2.0.0'));
    });

    test('stays idle when already on latest', () async {
      final client = MockClient(
        (_) async => http.Response(_releaseJson(tagName: 'v1.0.0'), 200),
      );
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.idle);
      expect(service.latestVersion, isNull);
    });

    test('stays idle when current is ahead of latest', () async {
      final client = MockClient(
        (_) async => http.Response(_releaseJson(tagName: 'v0.9.0'), 200),
      );
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.idle);
    });

    test('strips v prefix from tag_name', () async {
      final client = MockClient(
        (_) async => http.Response(_releaseJson(tagName: 'v3.1.4'), 200),
      );
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.latestVersion, '3.1.4');
    });

    test('handles tag without v prefix', () async {
      final client = MockClient(
        (_) async => http.Response(_releaseJson(tagName: '2.0.0'), 200),
      );
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.updateAvailable);
      expect(service.latestVersion, '2.0.0');
    });

    test('skips draft releases', () async {
      final client = MockClient(
        (_) async => http.Response(
          _releaseJson(tagName: 'v9.0.0', draft: true),
          200,
        ),
      );
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.idle);
      expect(service.latestVersion, isNull);
    });

    test('skips prerelease', () async {
      final client = MockClient(
        (_) async => http.Response(
          _releaseJson(tagName: 'v9.0.0', prerelease: true),
          200,
        ),
      );
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.idle);
    });

    test('sets error on HTTP 403 rate limit', () async {
      final client = MockClient((_) async => http.Response('', 403));
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.error);
      expect(service.errorMessage, contains('rate limit'));
    });

    test('sets error on HTTP 500', () async {
      final client = MockClient((_) async => http.Response('', 500));
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.error);
      expect(service.errorMessage, contains('500'));
    });

    test('sets error on invalid JSON', () async {
      final client = MockClient(
        (_) async => http.Response('not json', 200),
      );
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.error);
      expect(service.errorMessage, contains('Invalid response'));
    });

    test('sets error when tag_name is missing', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'draft': false, 'prerelease': false}),
          200,
        ),
      );
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.error);
      expect(service.errorMessage, contains('Invalid response'));
    });

    test('sets error on network failure', () async {
      final client = MockClient((_) => throw Exception('connection refused'));
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(service.status, UpdateStatus.error);
      expect(service.errorMessage, 'Update check failed');
    });

    test('notifies listeners during check', () async {
      final statuses = <UpdateStatus>[];
      final client = MockClient(
        (_) async => http.Response(_releaseJson(), 200),
      );
      final service = await _createService(client: client);
      service.addListener(() => statuses.add(service.status));

      await service.checkForUpdate();

      expect(statuses, contains(UpdateStatus.checking));
      expect(statuses.last, UpdateStatus.updateAvailable);
    });

    test('concurrent calls are deduplicated', () async {
      var requestCount = 0;
      final client = MockClient((_) async {
        requestCount++;
        return http.Response(_releaseJson(), 200);
      });
      final service = await _createService(client: client);

      await Future.wait([
        service.checkForUpdate(),
        service.checkForUpdate(),
      ]);

      expect(requestCount, 1);
    });

    test('sends correct Accept header', () async {
      String? acceptHeader;
      final client = MockClient((request) async {
        acceptHeader = request.headers['Accept'];
        return http.Response(_releaseJson(), 200);
      });
      final service = await _createService(client: client);

      await service.checkForUpdate();

      expect(acceptHeader, 'application/vnd.github+json');
    });
  });

  // ── Disposal ────────────────────────────────────────────────

  group('dispose', () {
    test('does not notify after disposal', () async {
      final client = MockClient(
        (_) async => http.Response(_releaseJson(), 200),
      );
      final service = await _createService(client: client);
      var notifyCount = 0;
      service.addListener(() => notifyCount++);

      await service.checkForUpdate();
      final countBeforeDispose = notifyCount;

      service.dispose();

      expect(countBeforeDispose, greaterThan(0));
    });
  });

  // ── Preferences ─────────────────────────────────────────────

  group('autoUpdateEnabled preference', () {
    test('defaults to true', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final prefs = PreferencesService(prefs: sp);
      expect(prefs.autoUpdateEnabled, isTrue);
    });

    test('round-trips false', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final prefs = PreferencesService(prefs: sp);
      await prefs.setAutoUpdateEnabled(false);
      expect(prefs.autoUpdateEnabled, isFalse);
    });

    test('notifies listeners on change', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final prefs = PreferencesService(prefs: sp);
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setAutoUpdateEnabled(false);
      expect(notified, isTrue);
    });
  });
}

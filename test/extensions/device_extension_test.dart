import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:lattice/extensions/device_extension.dart';

void main() {
  group('DeviceExtension', () {
    group('displayNameOrId', () {
      test('returns displayName when available', () {
        final device = Device(
          deviceId: 'ABCDEF',
          displayName: 'My Phone',
        );
        expect(device.displayNameOrId, 'My Phone');
      });

      test('falls back to deviceId when displayName is null', () {
        final device = Device(deviceId: 'ABCDEF');
        expect(device.displayNameOrId, 'ABCDEF');
      });
    });

    group('deviceIcon', () {
      test('returns phone icon for Android', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'Lattice Android',
        );
        expect(device.deviceIcon, Icons.phone_android_outlined);
      });

      test('returns iPhone icon for iOS', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'Element iOS',
        );
        expect(device.deviceIcon, Icons.phone_iphone_outlined);
      });

      test('returns iPhone icon for iPad', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'My iPad',
        );
        expect(device.deviceIcon, Icons.phone_iphone_outlined);
      });

      test('returns web icon for Firefox', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'Firefox on Ubuntu',
        );
        expect(device.deviceIcon, Icons.web_outlined);
      });

      test('returns web icon for Chrome', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'Chrome on Windows',
        );
        expect(device.deviceIcon, Icons.web_outlined);
      });

      test('returns desktop icon for Linux', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'Element Desktop Linux',
        );
        expect(device.deviceIcon, Icons.desktop_mac_outlined);
      });

      test('returns desktop icon for macOS', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'Lattice macOS',
        );
        expect(device.deviceIcon, Icons.desktop_mac_outlined);
      });

      test('returns desktop icon for Windows', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'Element Windows',
        );
        expect(device.deviceIcon, Icons.desktop_mac_outlined);
      });

      test('returns unknown icon for unrecognized name', () {
        final device = Device(
          deviceId: 'id',
          displayName: 'My Custom Client',
        );
        expect(device.deviceIcon, Icons.devices_other_outlined);
      });

      test('returns unknown icon when displayName is null', () {
        final device = Device(deviceId: 'id');
        expect(device.deviceIcon, Icons.devices_other_outlined);
      });
    });

    group('lastSeenDate', () {
      test('returns DateTime from lastSeenTs', () {
        final ts = DateTime(2025, 6, 15, 10, 30).millisecondsSinceEpoch;
        final device = Device(deviceId: 'id', lastSeenTs: ts);
        expect(device.lastSeenDate, DateTime(2025, 6, 15, 10, 30));
      });

      test('returns null when lastSeenTs is null', () {
        final device = Device(deviceId: 'id');
        expect(device.lastSeenDate, isNull);
      });
    });

    group('lastActiveString', () {
      test('returns "Unknown" when lastSeenTs is null', () {
        final device = Device(deviceId: 'id');
        expect(device.lastActiveString, 'Unknown');
      });

      test('returns "Active now" for recent activity', () {
        final ts = DateTime.now()
            .subtract(const Duration(minutes: 2))
            .millisecondsSinceEpoch;
        final device = Device(deviceId: 'id', lastSeenTs: ts);
        expect(device.lastActiveString, 'Active now');
      });

      test('returns minutes ago for activity within the hour', () {
        final ts = DateTime.now()
            .subtract(const Duration(minutes: 30))
            .millisecondsSinceEpoch;
        final device = Device(deviceId: 'id', lastSeenTs: ts);
        expect(device.lastActiveString, '30m ago');
      });

      test('returns hours ago for activity within the day', () {
        final ts = DateTime.now()
            .subtract(const Duration(hours: 5))
            .millisecondsSinceEpoch;
        final device = Device(deviceId: 'id', lastSeenTs: ts);
        expect(device.lastActiveString, '5h ago');
      });

      test('returns days ago for activity within 30 days', () {
        final ts = DateTime.now()
            .subtract(const Duration(days: 7))
            .millisecondsSinceEpoch;
        final device = Device(deviceId: 'id', lastSeenTs: ts);
        expect(device.lastActiveString, '7d ago');
      });

      test('returns date string for old activity', () {
        final ts =
            DateTime(2024, 3, 15).millisecondsSinceEpoch;
        final device = Device(deviceId: 'id', lastSeenTs: ts);
        expect(device.lastActiveString, '2024-03-15');
      });
    });
  });
}

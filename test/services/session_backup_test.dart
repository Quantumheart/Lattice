import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:lattice/services/session_backup.dart';

import 'matrix_service_test.mocks.dart';

void main() {
  late MockFlutterSecureStorage mockStorage;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
  });

  group('JSON serialization', () {
    test('round-trips all fields including nullable olmAccount', () {
      final backup = SessionBackup(
        accessToken: 'token123',
        userId: '@user:example.com',
        homeserver: 'https://example.com',
        deviceId: 'DEV1',
        deviceName: 'Lattice Flutter',
        olmAccount: 'pickled_olm_data',
      );

      final json = backup.toJson();
      final restored = SessionBackup.fromJson(json);

      expect(restored.accessToken, 'token123');
      expect(restored.userId, '@user:example.com');
      expect(restored.homeserver, 'https://example.com');
      expect(restored.deviceId, 'DEV1');
      expect(restored.deviceName, 'Lattice Flutter');
      expect(restored.olmAccount, 'pickled_olm_data');
    });

    test('round-trips with null optional fields', () {
      final backup = SessionBackup(
        accessToken: 'token123',
        userId: '@user:example.com',
        homeserver: 'https://example.com',
        deviceId: 'DEV1',
      );

      final json = backup.toJson();
      final restored = SessionBackup.fromJson(json);

      expect(restored.deviceName, isNull);
      expect(restored.olmAccount, isNull);
    });
  });

  group('save', () {
    test('writes JSON to secure storage with correct key', () async {
      final backup = SessionBackup(
        accessToken: 'token123',
        userId: '@user:example.com',
        homeserver: 'https://example.com',
        deviceId: 'DEV1',
      );

      await SessionBackup.save(
        backup,
        clientName: 'default',
        storage: mockStorage,
      );

      final captured = verify(mockStorage.write(
        key: 'lattice_session_backup_default',
        value: captureAnyNamed('value'),
      )).captured.single as String;

      final decoded = jsonDecode(captured) as Map<String, dynamic>;
      expect(decoded['accessToken'], 'token123');
      expect(decoded['userId'], '@user:example.com');
    });
  });

  group('load', () {
    test('returns SessionBackup when data exists', () async {
      final json = jsonEncode({
        'accessToken': 'token123',
        'userId': '@user:example.com',
        'homeserver': 'https://example.com',
        'deviceId': 'DEV1',
      });
      when(mockStorage.read(key: 'lattice_session_backup_default'))
          .thenAnswer((_) async => json);

      final result = await SessionBackup.load(
        clientName: 'default',
        storage: mockStorage,
      );

      expect(result, isNotNull);
      expect(result!.accessToken, 'token123');
      expect(result.userId, '@user:example.com');
    });

    test('returns null when no data exists', () async {
      when(mockStorage.read(key: 'lattice_session_backup_default'))
          .thenAnswer((_) async => null);

      final result = await SessionBackup.load(
        clientName: 'default',
        storage: mockStorage,
      );

      expect(result, isNull);
    });
  });

  group('delete', () {
    test('deletes from secure storage with correct key', () async {
      await SessionBackup.delete(
        clientName: 'default',
        storage: mockStorage,
      );

      verify(mockStorage.delete(key: 'lattice_session_backup_default'))
          .called(1);
    });
  });
}

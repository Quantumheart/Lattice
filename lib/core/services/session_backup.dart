import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A JSON-serializable snapshot of session credentials used to restore
/// a session after database corruption or failed init.
class SessionBackup {
  SessionBackup({
    required this.accessToken,
    required this.userId,
    required this.homeserver,
    required this.deviceId,
    this.deviceName,
    this.olmAccount,
  });

  final String accessToken;
  final String userId;
  final String homeserver;
  final String deviceId;
  final String? deviceName;
  final String? olmAccount;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'userId': userId,
        'homeserver': homeserver,
        'deviceId': deviceId,
        if (deviceName != null) 'deviceName': deviceName,
        if (olmAccount != null) 'olmAccount': olmAccount,
      };

  factory SessionBackup.fromJson(Map<String, dynamic> json) => SessionBackup(
        accessToken: json['accessToken'] as String,
        userId: json['userId'] as String,
        homeserver: json['homeserver'] as String,
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String?,
        olmAccount: json['olmAccount'] as String?,
      );

  // ── Storage helpers ──────────────────────────────────────────

  static String _storageKey(String clientName) =>
      'lattice_session_backup_$clientName';

  static Future<void> save(
    SessionBackup backup, {
    required String clientName,
    required FlutterSecureStorage storage,
  }) async {
    final json = jsonEncode(backup.toJson());
    await storage.write(key: _storageKey(clientName), value: json);
  }

  static Future<SessionBackup?> load({
    required String clientName,
    required FlutterSecureStorage storage,
  }) async {
    final json = await storage.read(key: _storageKey(clientName));
    if (json == null) return null;
    return SessionBackup.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );
  }

  static Future<void> delete({
    required String clientName,
    required FlutterSecureStorage storage,
  }) async {
    await storage.delete(key: _storageKey(clientName));
  }
}

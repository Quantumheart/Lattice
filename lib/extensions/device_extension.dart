import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Display helpers for [Device] objects from the Matrix SDK.
extension DeviceExtension on Device {
  /// Returns a user-friendly display name, falling back to the device ID.
  String get displayNameOrId => displayName ?? deviceId;

  /// Returns an appropriate icon based on the device display name.
  IconData get deviceIcon {
    final name = (displayName ?? '').toLowerCase();
    if (name.contains('android')) return Icons.phone_android_outlined;
    if (name.contains('ios') ||
        name.contains('iphone') ||
        name.contains('ipad')) {
      return Icons.phone_iphone_outlined;
    }
    if (name.contains('firefox') ||
        name.contains('chrome') ||
        name.contains('safari') ||
        name.contains('opera') ||
        name.contains('edge') ||
        name.contains('brave') ||
        name.contains('web')) {
      return Icons.web_outlined;
    }
    if (name.contains('windows') ||
        name.contains('macos') ||
        name.contains('mac os') ||
        name.contains('linux') ||
        name.contains('desktop') ||
        name.contains('electron')) {
      return Icons.desktop_mac_outlined;
    }
    return Icons.devices_other_outlined;
  }

  /// Returns the last-seen timestamp as a [DateTime], or null.
  DateTime? get lastSeenDate => lastSeenTs != null
      ? DateTime.fromMillisecondsSinceEpoch(lastSeenTs!)
      : null;

  /// Formats "last active" as a human-readable string.
  String get lastActiveString {
    final date = lastSeenDate;
    if (date == null) return 'Unknown';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 5) return 'Active now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

// ── Media cache (download/decrypt → temp file or memory) ──────

class MediaCache {
  static const _maxEntries = 50;
  static final LinkedHashMap<String, String> _tempFiles = LinkedHashMap();

  static Future<Media> resolve(Event event) async {
    final cached = _tempFiles[event.eventId];
    if (cached != null && !kIsWeb && File(cached).existsSync()) {
      _promote(event.eventId);
      return Media(cached);
    }

    if (event.isAttachmentEncrypted) {
      return _resolveEncrypted(event);
    }
    return _resolveUnencrypted(event);
  }

  static Future<Media> _resolveEncrypted(Event event) async {
    final file = await event.downloadAndDecryptAttachment();
    return _bytesToMedia(event.eventId, file.bytes);
  }

  static Future<Media> _resolveUnencrypted(Event event) async {
    final uri = await event.getAttachmentUri();
    if (uri == null) throw Exception('Failed to resolve attachment URI');
    return Media(uri.toString());
  }

  static Future<Media> _bytesToMedia(String eventId, Uint8List bytes) async {
    if (kIsWeb) {
      return Media.memory(bytes);
    }
    final dir = await getTemporaryDirectory();
    final sanitized = eventId.replaceAll(RegExp(r'[^\w]'), '_');
    final path = '${dir.path}/lattice_media_$sanitized';
    final file = File(path);
    await file.writeAsBytes(bytes);
    _tempFiles[eventId] = path;
    _evictOldest();
    return Media(path);
  }

  static void _promote(String eventId) {
    final path = _tempFiles.remove(eventId);
    if (path != null) _tempFiles[eventId] = path;
  }

  static void _evictOldest() {
    while (_tempFiles.length > _maxEntries) {
      final oldest = _tempFiles.keys.first;
      evict(oldest);
    }
  }

  static void evict(String eventId) {
    final path = _tempFiles.remove(eventId);
    if (path != null && !kIsWeb) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }

  static void clearAll() {
    for (final path in _tempFiles.values) {
      if (!kIsWeb) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    }
    _tempFiles.clear();
  }
}

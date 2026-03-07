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

    final file = await event.downloadAndDecryptAttachment();
    final mimetype = event.content
        .tryGet<Map<String, Object?>>('info')
        ?.tryGet<String>('mimetype');
    return _bytesToMedia(event.eventId, file.bytes, mimetype);
  }

  static Future<Media> _bytesToMedia(
      String eventId, Uint8List bytes, String? mimetype,) async {
    if (kIsWeb) {
      return Media.memory(bytes);
    }
    final dir = await getTemporaryDirectory();
    final sanitized = eventId.replaceAll(RegExp(r'[^\w]'), '_');
    final ext = _extensionForMime(mimetype);
    final path = '${dir.path}/lattice_media_$sanitized$ext';
    final file = File(path);
    await file.writeAsBytes(bytes);
    _tempFiles[eventId] = path;
    _evictOldest();
    return Media(path);
  }

  static String _extensionForMime(String? mime) {
    if (mime == null) return '';
    return switch (mime) {
      'audio/ogg' => '.ogg',
      'audio/opus' => '.opus',
      'audio/mpeg' => '.mp3',
      'audio/mp4' => '.m4a',
      'audio/aac' => '.aac',
      'audio/wav' => '.wav',
      'audio/webm' => '.webm',
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      'video/quicktime' => '.mov',
      _ => '',
    };
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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

// ── OpenGraph data model ─────────────────────────────────────

class OpenGraphData {
  const OpenGraphData({
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    required this.url,
  });

  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String url;

  bool get isEmpty => title == null && description == null && imageUrl == null;
}

// ── OpenGraph fetching service ───────────────────────────────

class OpenGraphService {
  static const _maxCacheSize = 200;
  static const _fetchTimeout = Duration(seconds: 5);
  static const _maxBytes = 50 * 1024; // 50 KB

  /// LRU cache: URL → fetched data (null = failed/no data).
  final _cache = <String, OpenGraphData?>{};
  // Use as LinkedHashMap (Dart default) for LRU key ordering.

  /// In-flight requests to deduplicate concurrent fetches.
  final _inFlight = <String, Future<OpenGraphData?>>{};

  /// Fetch OpenGraph metadata for the given [url].
  ///
  /// Returns `null` if the URL is unsupported, unreachable, or has no OG tags.
  Future<OpenGraphData?> fetch(String url) async {
    if (!_isSupported(url)) return null;

    // Cache hit — move to end for LRU behaviour.
    if (_cache.containsKey(url)) {
      final cached = _cache.remove(url);
      _cache[url] = cached;
      return cached;
    }

    // Deduplicate concurrent fetches for the same URL.
    if (_inFlight.containsKey(url)) return _inFlight[url];

    final future = _doFetch(url);
    _inFlight[url] = future;
    try {
      final result = await future;
      _putCache(url, result);
      return result;
    } finally {
      _inFlight.remove(url);
    }
  }

  // ── Internal helpers ───────────────────────────────────────

  bool _isSupported(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    // Skip Matrix links and data URIs.
    if (uri.host == 'matrix.to') return false;
    return true;
  }

  Future<OpenGraphData?> _doFetch(String url) async {
    try {
      final uri = Uri.parse(url);
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = 'Lattice/1.0 (Flutter Matrix client)';

      final client = http.Client();
      try {
        final streamed =
            await client.send(request).timeout(_fetchTimeout);

        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          return null;
        }

        // Read only the first ~50 KB to avoid downloading huge pages.
        final bytes = <int>[];
        await for (final chunk in streamed.stream) {
          bytes.addAll(chunk);
          if (bytes.length >= _maxBytes) break;
        }

        final body = utf8.decode(bytes, allowMalformed: true);
        return _parse(body, url);
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[Lattice] OpenGraph fetch failed for $url: $e');
      return null;
    }
  }

  OpenGraphData? _parse(String html, String url) {
    final document = html_parser.parse(html);
    final metas = document.querySelectorAll('meta');

    String? ogTitle;
    String? ogDescription;
    String? ogImage;
    String? ogSiteName;

    for (final meta in metas) {
      final property = meta.attributes['property'] ?? '';
      final content = meta.attributes['content'];
      if (content == null || content.isEmpty) continue;

      switch (property) {
        case 'og:title':
          ogTitle = content;
        case 'og:description':
          ogDescription = content;
        case 'og:image':
          ogImage = content;
        case 'og:site_name':
          ogSiteName = content;
      }
    }

    // Fall back to <title> tag if no og:title.
    ogTitle ??= document.querySelector('title')?.text;

    final data = OpenGraphData(
      title: ogTitle,
      description: ogDescription,
      imageUrl: ogImage,
      siteName: ogSiteName,
      url: url,
    );

    return data.isEmpty ? null : data;
  }

  void _putCache(String url, OpenGraphData? data) {
    // Evict oldest entry if at capacity.
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = data;
  }
}

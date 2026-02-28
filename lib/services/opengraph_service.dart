import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

// ── OpenGraph data model ─────────────────────────────────────

class OpenGraphData {
  OpenGraphData({
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    required this.url,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String url;
  final DateTime fetchedAt;

  bool get isEmpty => title == null && description == null && imageUrl == null;
}

// ── OpenGraph fetching service ───────────────────────────────

class OpenGraphService {
  OpenGraphService({http.Client? client}) : _client = client ?? http.Client();

  static const _maxCacheSize = 200;
  static const _fetchTimeout = Duration(seconds: 5);
  static const _maxBytes = 50 * 1024; // 50 KB
  static const _maxRedirects = 5;
  static const _cacheTtl = Duration(minutes: 30);

  /// LRU cache: URL → fetched data (null = failed/no data).
  final _cache = <String, OpenGraphData?>{};
  // Use as LinkedHashMap (Dart default) for LRU key ordering.

  /// In-flight requests to deduplicate concurrent fetches.
  final _inFlight = <String, Future<OpenGraphData?>>{};

  /// Reusable HTTP client for connection pooling.
  final http.Client _client;

  /// Close the underlying HTTP client. Call when the service is disposed.
  void dispose() => _client.close();

  /// Fetch OpenGraph metadata for the given [url].
  ///
  /// Returns `null` if the URL is unsupported, unreachable, or has no OG tags.
  Future<OpenGraphData?> fetch(String url) async {
    if (!_isSupported(url)) return null;

    // Cache hit — move to end for LRU behaviour.
    if (_cache.containsKey(url)) {
      final cached = _cache.remove(url);
      // Evict stale entries.
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) > _cacheTtl) {
        // Fall through to re-fetch.
      } else {
        _cache[url] = cached;
        return cached;
      }
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

  @visibleForTesting
  static bool isSupported(String url) => _isSupported(url);

  static bool _isSupported(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    // Skip Matrix links.
    if (uri.host == 'matrix.to') return false;
    // Reject obvious private/loopback hostnames.
    if (_isPrivateHost(uri.host)) return false;
    return true;
  }

  /// Returns `true` if [host] is a known private or loopback hostname.
  @visibleForTesting
  static bool isPrivateHost(String host) => _isPrivateHost(host);

  static bool _isPrivateHost(String host) {
    if (host == 'localhost') return true;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return false;
    return _isPrivateAddress(ip);
  }

  /// Returns `true` if [address] is loopback, link-local, or RFC 1918 private.
  @visibleForTesting
  static bool isPrivateAddress(InternetAddress address) =>
      _isPrivateAddress(address);

  static bool _isPrivateAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    if (address.type == InternetAddressType.IPv4) {
      final bytes = address.rawAddress;
      // 10.0.0.0/8
      if (bytes[0] == 10) return true;
      // 172.16.0.0/12
      if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) return true;
      // 192.168.0.0/16
      if (bytes[0] == 192 && bytes[1] == 168) return true;
      // 169.254.0.0/16 (link-local / cloud metadata)
      if (bytes[0] == 169 && bytes[1] == 254) return true;
    }
    if (address.type == InternetAddressType.IPv6) {
      final bytes = address.rawAddress;
      // fc00::/7 (unique local)
      if ((bytes[0] & 0xFE) == 0xFC) return true;
      // fe80::/10 (link-local)
      if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) return true;
    }
    return false;
  }

  /// Resolves [host] and returns the list of public addresses.
  /// Returns `null` if any resolved address is private (SSRF protection).
  Future<List<InternetAddress>?> _resolvePublicAddresses(String host) async {
    final addresses =
        await InternetAddress.lookup(host).timeout(_fetchTimeout);
    if (addresses.isEmpty) return null;
    if (addresses.any((a) => _isPrivateAddress(a))) {
      debugPrint('[Lattice] OpenGraph blocked private IP for $host');
      return null;
    }
    return addresses;
  }

  /// Sends a GET request to [uri], connecting via [pinnedAddress] to prevent
  /// DNS rebinding attacks. The Host header is set to the original hostname.
  Future<http.StreamedResponse> _sendPinned(
      Uri uri, InternetAddress pinnedAddress) async {
    // Rewrite the URI to connect to the pinned IP directly.
    final pinnedUri = uri.replace(host: pinnedAddress.address);
    final request = http.Request('GET', pinnedUri)
      ..headers['User-Agent'] = 'Lattice/1.0 (Flutter Matrix client)'
      ..headers['Host'] = uri.host
      ..followRedirects = false;
    return _client.send(request).timeout(_fetchTimeout);
  }

  Future<OpenGraphData?> _doFetch(String url) async {
    try {
      var uri = Uri.parse(url);

      for (var i = 0; i <= _maxRedirects; i++) {
        // DNS lookup to prevent SSRF — pin the resolved IP for the request.
        final addresses = await _resolvePublicAddresses(uri.host);
        if (addresses == null) return null;

        final streamed = await _sendPinned(uri, addresses.first);

        if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
          if (i == _maxRedirects) return null; // Too many redirects.
          final location = streamed.headers['location'];
          if (location == null) return null;
          uri = uri.resolve(location);
          if (uri.scheme != 'http' && uri.scheme != 'https') return null;
          if (_isPrivateHost(uri.host)) return null;
          continue;
        }

        return _readResponse(streamed, url);
      }

      return null;
    } catch (e) {
      debugPrint('[Lattice] OpenGraph fetch failed for $url: $e');
      return null;
    }
  }

  Future<OpenGraphData?> _readResponse(
      http.StreamedResponse response, String url) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    // Only parse HTML responses.
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('text/html') &&
        !contentType.contains('application/xhtml')) {
      return null;
    }

    // Read only the first ~50 KB to avoid downloading huge pages.
    final bytes = <int>[];
    try {
      late final StreamSubscription<List<int>> subscription;
      subscription = response.stream.listen((chunk) {
        bytes.addAll(chunk);
        if (bytes.length >= _maxBytes) subscription.cancel();
      });
      await subscription.asFuture<void>().timeout(
        _fetchTimeout,
        onTimeout: () => subscription.cancel(),
      );
    } catch (_) {
      // Stream cancelled or timed out — parse whatever we have.
    }
    final truncated =
        bytes.length > _maxBytes ? bytes.sublist(0, _maxBytes) : bytes;
    if (truncated.isEmpty) return null;

    final body = utf8.decode(truncated, allowMalformed: true);
    return _parse(body, url);
  }

  @visibleForTesting
  OpenGraphData? parse(String html, String url) => _parse(html, url);

  OpenGraphData? _parse(String html, String url) {
    final document = html_parser.parse(html);
    final metas = document.querySelectorAll('meta');

    String? ogTitle;
    String? ogDescription;
    String? ogImage;
    String? ogSiteName;

    for (final meta in metas) {
      final property = meta.attributes['property'] ?? '';
      final name = meta.attributes['name'] ?? '';
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

      // Fall back to <meta name="description"> if no og:description.
      if (name == 'description' && ogDescription == null) {
        ogDescription = content;
      }
    }

    // Fall back to <title> tag if no og:title.
    ogTitle ??= document.querySelector('title')?.text;

    // Resolve relative og:image URLs against the page origin.
    if (ogImage != null) {
      final imageUri = Uri.tryParse(ogImage);
      if (imageUri != null && !imageUri.hasScheme) {
        final base = Uri.tryParse(url);
        if (base != null) {
          ogImage = base.resolve(ogImage).toString();
        }
      }
    }

    // Validate og:image URL — reject private/non-http(s) schemes.
    if (ogImage != null && !_isSupported(ogImage)) {
      ogImage = null;
    }

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

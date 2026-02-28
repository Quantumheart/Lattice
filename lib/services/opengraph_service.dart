import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  /// Reusable HTTP client for connection pooling.
  final _client = http.Client();

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
    // Skip Matrix links.
    if (uri.host == 'matrix.to') return false;
    // Reject obvious private/loopback hostnames.
    if (_isPrivateHost(uri.host)) return false;
    return true;
  }

  /// Returns `true` if [host] is a known private or loopback hostname.
  static bool _isPrivateHost(String host) {
    if (host == 'localhost') return true;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return false;
    return _isPrivateAddress(ip);
  }

  /// Returns `true` if [address] is loopback, link-local, or RFC 1918 private.
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

  /// Validates that a URI resolves only to public IPs. Returns `false` if
  /// any resolved address is private (SSRF protection).
  Future<bool> _resolvedToPublicIp(Uri uri) async {
    final addresses = await InternetAddress.lookup(uri.host)
        .timeout(_fetchTimeout);
    if (addresses.isEmpty) return false;
    if (addresses.any((a) => _isPrivateAddress(a))) {
      debugPrint('[Lattice] OpenGraph blocked private IP for $uri');
      return false;
    }
    return true;
  }

  Future<OpenGraphData?> _doFetch(String url) async {
    try {
      final uri = Uri.parse(url);

      // DNS lookup to prevent SSRF via attacker-controlled hostnames
      // that resolve to private IPs.
      if (!await _resolvedToPublicIp(uri)) return null;

      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = 'Lattice/1.0 (Flutter Matrix client)'
        ..followRedirects = false;

      final streamed =
          await _client.send(request).timeout(_fetchTimeout);

      // Handle redirects manually to validate each hop against SSRF.
      if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
        final location = streamed.headers['location'];
        if (location == null) return null;
        final redirectUri = uri.resolve(location);
        if (redirectUri.scheme != 'http' && redirectUri.scheme != 'https') {
          return null;
        }
        if (_isPrivateHost(redirectUri.host)) return null;
        if (!await _resolvedToPublicIp(redirectUri)) return null;
        // Follow the single redirect.
        final redirectRequest = http.Request('GET', redirectUri)
          ..headers['User-Agent'] = 'Lattice/1.0 (Flutter Matrix client)'
          ..followRedirects = false;
        final redirected =
            await _client.send(redirectRequest).timeout(_fetchTimeout);
        return _readResponse(redirected, url);
      }

      return _readResponse(streamed, url);
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
    late final StreamSubscription<List<int>> subscription;
    subscription = response.stream.listen((chunk) {
      bytes.addAll(chunk);
      if (bytes.length >= _maxBytes) subscription.cancel();
    });
    await subscription.asFuture<void>().timeout(
      _fetchTimeout,
      onTimeout: () => subscription.cancel(),
    );
    final truncated =
        bytes.length > _maxBytes ? bytes.sublist(0, _maxBytes) : bytes;

    final body = utf8.decode(truncated, allowMalformed: true);
    return _parse(body, url);
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

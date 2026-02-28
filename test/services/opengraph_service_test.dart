import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lattice/services/opengraph_service.dart';

/// A public IPv4 address used for DNS override in tests.
final _publicIp = InternetAddress('93.184.216.34');

/// Creates an [OpenGraphService] with a mock HTTP client and fake DNS.
/// The [handler] receives every HTTP request and returns a response.
OpenGraphService _createTestService(
  http.Response Function(http.Request) handler,
) {
  final mockClient = MockClient((request) async => handler(request));
  final service = OpenGraphService(client: mockClient)
    ..dnsResolver = (_) async => [_publicIp];
  return service;
}

/// Builds a minimal HTML page with the given OG meta tags.
String _ogHtml({String? title, String? description, String? image}) {
  final buf = StringBuffer('<html><head>');
  if (title != null) {
    buf.write('<meta property="og:title" content="$title">');
  }
  if (description != null) {
    buf.write('<meta property="og:description" content="$description">');
  }
  if (image != null) {
    buf.write('<meta property="og:image" content="$image">');
  }
  buf.write('</head><body></body></html>');
  return buf.toString();
}

void main() {
  late OpenGraphService service;

  setUp(() {
    service = OpenGraphService();
  });

  tearDown(() {
    service.dispose();
  });

  // ── _isPrivateHost ──────────────────────────────────────────

  group('isPrivateHost', () {
    test('blocks localhost', () {
      expect(OpenGraphService.isPrivateHost('localhost'), isTrue);
    });

    test('blocks 127.0.0.1', () {
      expect(OpenGraphService.isPrivateHost('127.0.0.1'), isTrue);
    });

    test('blocks 10.x.x.x', () {
      expect(OpenGraphService.isPrivateHost('10.0.0.1'), isTrue);
      expect(OpenGraphService.isPrivateHost('10.255.255.255'), isTrue);
    });

    test('blocks 172.16-31.x.x', () {
      expect(OpenGraphService.isPrivateHost('172.16.0.1'), isTrue);
      expect(OpenGraphService.isPrivateHost('172.31.255.255'), isTrue);
      expect(OpenGraphService.isPrivateHost('172.15.0.1'), isFalse);
      expect(OpenGraphService.isPrivateHost('172.32.0.1'), isFalse);
    });

    test('blocks 192.168.x.x', () {
      expect(OpenGraphService.isPrivateHost('192.168.0.1'), isTrue);
      expect(OpenGraphService.isPrivateHost('192.168.255.255'), isTrue);
    });

    test('blocks 169.254.x.x (link-local / cloud metadata)', () {
      expect(OpenGraphService.isPrivateHost('169.254.169.254'), isTrue);
      expect(OpenGraphService.isPrivateHost('169.254.0.1'), isTrue);
    });

    test('allows public IPs', () {
      expect(OpenGraphService.isPrivateHost('8.8.8.8'), isFalse);
      expect(OpenGraphService.isPrivateHost('1.1.1.1'), isFalse);
      expect(OpenGraphService.isPrivateHost('93.184.216.34'), isFalse);
    });

    test('allows regular hostnames', () {
      expect(OpenGraphService.isPrivateHost('example.com'), isFalse);
      expect(OpenGraphService.isPrivateHost('github.com'), isFalse);
    });
  });

  // ── _isPrivateAddress IPv6 ─────────────────────────────────

  group('isPrivateAddress IPv6', () {
    test('blocks IPv6 unique local (fc00::/7)', () {
      final addr = InternetAddress('fd12:3456:789a::1');
      expect(OpenGraphService.isPrivateAddress(addr), isTrue);
    });

    test('blocks IPv6 link-local (fe80::/10)', () {
      final addr = InternetAddress('fe80::1');
      expect(OpenGraphService.isPrivateAddress(addr), isTrue);
    });

    test('blocks IPv6 loopback (::1)', () {
      final addr = InternetAddress('::1');
      expect(OpenGraphService.isPrivateAddress(addr), isTrue);
    });
  });

  // ── _isSupported ───────────────────────────────────────────

  group('isSupported', () {
    test('allows http and https URLs', () {
      expect(OpenGraphService.isSupported('https://example.com'), isTrue);
      expect(OpenGraphService.isSupported('http://example.com'), isTrue);
    });

    test('rejects non-http schemes', () {
      expect(OpenGraphService.isSupported('ftp://example.com'), isFalse);
      expect(OpenGraphService.isSupported('file:///etc/passwd'), isFalse);
      expect(OpenGraphService.isSupported('javascript:alert(1)'), isFalse);
    });

    test('rejects matrix.to links', () {
      expect(
        OpenGraphService.isSupported('https://matrix.to/#/@user:server'),
        isFalse,
      );
    });

    test('rejects private hosts', () {
      expect(
        OpenGraphService.isSupported('http://localhost:8080'),
        isFalse,
      );
      expect(
        OpenGraphService.isSupported('http://192.168.1.1'),
        isFalse,
      );
      expect(
        OpenGraphService.isSupported('http://169.254.169.254/metadata'),
        isFalse,
      );
    });

    test('rejects empty/invalid URLs', () {
      expect(OpenGraphService.isSupported(''), isFalse);
      expect(OpenGraphService.isSupported('not a url'), isFalse);
    });
  });

  // ── _parse ─────────────────────────────────────────────────

  group('parse', () {
    test('extracts og:title and og:description', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="Test Title">
          <meta property="og:description" content="Test Description">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com');
      expect(data, isNotNull);
      expect(data!.title, 'Test Title');
      expect(data.description, 'Test Description');
    });

    test('extracts og:image and og:site_name', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="Title">
          <meta property="og:image" content="https://example.com/img.png">
          <meta property="og:site_name" content="Example">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com');
      expect(data!.imageUrl, 'https://example.com/img.png');
      expect(data.siteName, 'Example');
    });

    test('falls back to <title> when no og:title', () {
      const html = '''
        <html><head>
          <title>Fallback Title</title>
          <meta property="og:description" content="Desc">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com');
      expect(data!.title, 'Fallback Title');
    });

    test('falls back to meta description when no og:description', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="Title">
          <meta name="description" content="Meta Desc">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com');
      expect(data!.description, 'Meta Desc');
    });

    test('resolves relative og:image URLs', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="Title">
          <meta property="og:image" content="/images/thumb.png">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com/page');
      expect(data!.imageUrl, 'https://example.com/images/thumb.png');
    });

    test('returns null when no OG data found', () {
      const html = '<html><head></head><body>Hello</body></html>';
      final data = service.parse(html, 'https://example.com');
      expect(data, isNull);
    });

    test('rejects og:image pointing to private IP', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="Title">
          <meta property="og:image" content="http://192.168.1.1/img.png">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com');
      expect(data, isNotNull);
      expect(data!.imageUrl, isNull);
    });

    test('rejects og:image with file:// scheme', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="Title">
          <meta property="og:image" content="file:///etc/passwd">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com');
      expect(data!.imageUrl, isNull);
    });

    test('rejects og:image pointing to localhost', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="Title">
          <meta property="og:image" content="http://localhost:8080/img.png">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com');
      expect(data!.imageUrl, isNull);
    });

    test('rejects og:image pointing to cloud metadata endpoint', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="Title">
          <meta property="og:image" content="http://169.254.169.254/latest/meta-data/">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com');
      expect(data!.imageUrl, isNull);
    });

    test('skips empty content attributes', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="">
          <meta property="og:description" content="Valid">
        </head><body></body></html>
      ''';
      final data = service.parse(html, 'https://example.com');
      expect(data!.title, isNull);
      expect(data.description, 'Valid');
    });
  });

  // ── Cache TTL ──────────────────────────────────────────────

  group('OpenGraphData', () {
    test('records fetchedAt timestamp', () {
      final before = DateTime.now();
      final data = OpenGraphData(url: 'https://example.com', title: 'T');
      final after = DateTime.now();
      expect(data.fetchedAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(data.fetchedAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('isEmpty returns true when no title/description/image', () {
      final data = OpenGraphData(url: 'https://example.com');
      expect(data.isEmpty, isTrue);
    });

    test('isEmpty returns false when title is set', () {
      final data = OpenGraphData(url: 'https://example.com', title: 'T');
      expect(data.isEmpty, isFalse);
    });
  });

  // ── Network fetch path ─────────────────────────────────────

  group('fetch (mock HTTP)', () {
    test('returns parsed OG data for a valid HTML response', () async {
      final svc = _createTestService((_) => http.Response(
            _ogHtml(title: 'Hello', description: 'World'),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ));
      addTearDown(svc.dispose);

      final data = await svc.fetch('https://example.com/page');
      expect(data, isNotNull);
      expect(data!.title, 'Hello');
      expect(data.description, 'World');
    });

    test('returns null for non-HTML content-type', () async {
      final svc = _createTestService((_) => http.Response(
            '{"key": "value"}',
            200,
            headers: {'content-type': 'application/json'},
          ));
      addTearDown(svc.dispose);

      final data = await svc.fetch('https://example.com/api');
      expect(data, isNull);
    });

    test('returns null for non-2xx status codes', () async {
      final svc = _createTestService((_) => http.Response('Not found', 404,
          headers: {'content-type': 'text/html'}));
      addTearDown(svc.dispose);

      final data = await svc.fetch('https://example.com/missing');
      expect(data, isNull);
    });

    test('follows redirects up to the limit', () async {
      var callCount = 0;
      final svc = _createTestService((request) {
        callCount++;
        if (callCount < 3) {
          return http.Response('', 302, headers: {
            'location': 'https://example.com/step$callCount',
          });
        }
        return http.Response(
          _ogHtml(title: 'Final'),
          200,
          headers: {'content-type': 'text/html'},
        );
      });
      addTearDown(svc.dispose);

      final data = await svc.fetch('https://example.com/start');
      expect(data, isNotNull);
      expect(data!.title, 'Final');
      expect(callCount, 3);
    });

    test('returns null when redirect target is a private host', () async {
      final svc = _createTestService((_) => http.Response('', 302, headers: {
            'location': 'http://localhost:8080/internal',
          }));
      addTearDown(svc.dispose);

      final data = await svc.fetch('https://example.com/redirect');
      expect(data, isNull);
    });

    test('returns null when redirect has no location header', () async {
      final svc =
          _createTestService((_) => http.Response('', 301, headers: {}));
      addTearDown(svc.dispose);

      final data = await svc.fetch('https://example.com/redirect');
      expect(data, isNull);
    });

    test('returns null when DNS resolves to private IP', () async {
      final mockClient = MockClient((_) async => http.Response(
            _ogHtml(title: 'Should not reach'),
            200,
            headers: {'content-type': 'text/html'},
          ));
      final svc = OpenGraphService(client: mockClient)
        ..dnsResolver = (_) async => [InternetAddress('10.0.0.1')];
      addTearDown(svc.dispose);

      final data = await svc.fetch('https://example.com');
      expect(data, isNull);
    });

    test('caches results and returns cached data on second call', () async {
      var callCount = 0;
      final svc = _createTestService((_) {
        callCount++;
        return http.Response(
          _ogHtml(title: 'Cached'),
          200,
          headers: {'content-type': 'text/html'},
        );
      });
      addTearDown(svc.dispose);

      final first = await svc.fetch('https://example.com');
      final second = await svc.fetch('https://example.com');
      expect(first!.title, 'Cached');
      expect(second!.title, 'Cached');
      expect(callCount, 1);
    });

    test('caches negative results and does not re-fetch', () async {
      var callCount = 0;
      final svc = _createTestService((_) {
        callCount++;
        return http.Response('Not found', 404,
            headers: {'content-type': 'text/html'});
      });
      addTearDown(svc.dispose);

      final first = await svc.fetch('https://example.com/missing');
      final second = await svc.fetch('https://example.com/missing');
      expect(first, isNull);
      expect(second, isNull);
      expect(callCount, 1);
    });

    test('truncates response body at 50 KB', () async {
      // Build HTML where OG tags are within the first 50 KB.
      final padding = 'x' * (60 * 1024); // 60 KB of padding after tags.
      final html = _ogHtml(title: 'Big Page') + padding;
      final svc = _createTestService((_) => http.Response(
            html,
            200,
            headers: {'content-type': 'text/html'},
          ));
      addTearDown(svc.dispose);

      final data = await svc.fetch('https://example.com/big');
      expect(data, isNotNull);
      expect(data!.title, 'Big Page');
    });

    test('returns null for unsupported URL schemes', () async {
      final svc = _createTestService((_) => http.Response('', 200));
      addTearDown(svc.dispose);

      expect(await svc.fetch('ftp://example.com'), isNull);
      expect(await svc.fetch('file:///etc/passwd'), isNull);
    });

    test('strips og:image when image host resolves to private IP', () async {
      var requestCount = 0;
      final svc = _createTestService((_) => http.Response(
            _ogHtml(
                title: 'Title',
                image: 'https://evil-cdn.example.com/img.png'),
            200,
            headers: {'content-type': 'text/html'},
          ));
      // First DNS call (page host) returns public, second (image host) returns private.
      var dnsCallCount = 0;
      svc.dnsResolver = (host) async {
        dnsCallCount++;
        if (dnsCallCount == 1) return [_publicIp];
        // Image host resolves to a private IP.
        return [InternetAddress('10.0.0.1')];
      };
      addTearDown(svc.dispose);

      final data = await svc.fetch('https://example.com');
      expect(data, isNotNull);
      expect(data!.title, 'Title');
      expect(data.imageUrl, isNull);
    });

    test('deduplicates concurrent fetches for the same URL', () async {
      var callCount = 0;
      final svc = _createTestService((_) {
        callCount++;
        return http.Response(
          _ogHtml(title: 'Dedup'),
          200,
          headers: {'content-type': 'text/html'},
        );
      });
      addTearDown(svc.dispose);

      final results = await Future.wait([
        svc.fetch('https://example.com'),
        svc.fetch('https://example.com'),
        svc.fetch('https://example.com'),
      ]);
      expect(results.every((r) => r!.title == 'Dedup'), isTrue);
      expect(callCount, 1);
    });
  });
}

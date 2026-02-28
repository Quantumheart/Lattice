import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/services/opengraph_service.dart';

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
}

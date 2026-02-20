import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/services/sso_callback_server.dart';

void main() {
  group('SsoCallbackServer', () {
    test('starts and returns a callback URL', () async {
      final server = SsoCallbackServer();
      final url = await server.start();

      expect(url, startsWith('http://127.0.0.1:'));
      expect(url, endsWith('/callback'));

      server.tokenFuture.catchError((_) => '');
      server.dispose();
    });

    test('captures loginToken from GET /callback', () async {
      final server = SsoCallbackServer();
      final url = await server.start();

      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('$url?loginToken=test_token_123'));
        final response = await request.close();

        expect(response.statusCode, HttpStatus.ok);

        final body = await response.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        );
        final html = String.fromCharCodes(body);
        expect(html, contains('Login successful'));

        final token = await server.tokenFuture;
        expect(token, 'test_token_123');
      } finally {
        client.close();
        server.dispose();
      }
    });

    test('returns error page when loginToken is missing', () async {
      final server = SsoCallbackServer();
      final url = await server.start();

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();

        expect(response.statusCode, HttpStatus.badRequest);

        final body = await response.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        );
        final html = String.fromCharCodes(body);
        expect(html, contains('Login failed'));
      } finally {
        client.close();
        server.tokenFuture.catchError((_) => '');
        server.dispose();
      }
    });

    test('returns 404 for unknown paths', () async {
      final server = SsoCallbackServer();
      final baseUrl = await server.start();
      // Strip /callback and add /unknown
      final baseUri = Uri.parse(baseUrl);
      final unknownUrl = baseUri.replace(path: '/unknown');

      final client = HttpClient();
      try {
        final request = await client.getUrl(unknownUrl);
        final response = await request.close();

        expect(response.statusCode, HttpStatus.notFound);
      } finally {
        client.close();
        server.tokenFuture.catchError((_) => '');
        server.dispose();
      }
    });

    test('errors tokenFuture when disposed before token arrives', () async {
      final server = SsoCallbackServer();
      await server.start();

      server.dispose();

      expect(server.tokenFuture, throwsA(isA<SsoException>()));
    });

    test('dispose is idempotent', () async {
      final server = SsoCallbackServer();
      await server.start();

      server.tokenFuture.catchError((_) => '');

      server.dispose();
      server.dispose();
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/services/recaptcha_server.dart';

void main() {
  group('RecaptchaServer', () {
    test('starts and serves HTML page at GET /', () async {
      final server = RecaptchaServer(siteKey: 'testkey');
      final url = await server.start();

      expect(url, startsWith('http://127.0.0.1:'));

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();

        expect(response.statusCode, HttpStatus.ok);

        final body = await response.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        );
        final html = String.fromCharCodes(body);
        expect(html, contains('data-sitekey="testkey"'));
        expect(html, contains('g-recaptcha'));
      } finally {
        client.close();
        // Catch the cancelled error from tokenFuture since we never posted a token.
        server.tokenFuture.catchError((_) => '');
        server.dispose();
      }
    });

    test('captures token from POST /token', () async {
      final server = RecaptchaServer(siteKey: 'testkey');
      final url = await server.start();

      final client = HttpClient();
      try {
        final request = await client.postUrl(Uri.parse('${url}token'));
        request.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded');
        request.write('g-recaptcha-response=mytesttoken');
        final response = await request.close();

        expect(response.statusCode, HttpStatus.ok);

        final token = await server.tokenFuture;
        expect(token, 'mytesttoken');
      } finally {
        client.close();
        server.dispose();
      }
    });

    test('rejects POST /token with missing token', () async {
      final server = RecaptchaServer(siteKey: 'testkey');
      final url = await server.start();

      final client = HttpClient();
      try {
        final request = await client.postUrl(Uri.parse('${url}token'));
        request.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded');
        request.write('other=value');
        final response = await request.close();

        expect(response.statusCode, HttpStatus.badRequest);
      } finally {
        client.close();
        server.tokenFuture.catchError((_) => '');
        server.dispose();
      }
    });

    test('returns 404 for unknown paths', () async {
      final server = RecaptchaServer(siteKey: 'testkey');
      final url = await server.start();

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('${url}unknown'));
        final response = await request.close();

        expect(response.statusCode, HttpStatus.notFound);
      } finally {
        client.close();
        server.tokenFuture.catchError((_) => '');
        server.dispose();
      }
    });

    test('errors tokenFuture when disposed before token arrives', () async {
      final server = RecaptchaServer(siteKey: 'testkey');
      await server.start();

      server.dispose();

      expect(server.tokenFuture, throwsA(isA<RecaptchaException>()));
    });

    test('dispose is idempotent', () async {
      final server = RecaptchaServer(siteKey: 'testkey');
      await server.start();

      // Catch the error from tokenFuture before disposing.
      server.tokenFuture.catchError((_) => '');

      // Should not throw when called multiple times.
      server.dispose();
      server.dispose();
    });
  });
}

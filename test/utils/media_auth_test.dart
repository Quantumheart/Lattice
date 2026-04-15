import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/media_auth.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>()])
import 'media_auth_test.mocks.dart';

void main() {
  late MockClient mockClient;

  setUp(() {
    mockClient = MockClient();
  });

  group('mediaAuthHeaders', () {
    test('returns Bearer header when host and port match homeserver', () {
      when(mockClient.homeserver)
          .thenReturn(Uri.parse('https://matrix.example.com'));
      when(mockClient.accessToken).thenReturn('secret-token');

      final headers = mediaAuthHeaders(
        mockClient,
        'https://matrix.example.com/_matrix/media/v3/download/abc',
      );

      expect(headers, {'authorization': 'Bearer secret-token'});
    });

    test('returns null when host differs', () {
      when(mockClient.homeserver)
          .thenReturn(Uri.parse('https://matrix.example.com'));
      when(mockClient.accessToken).thenReturn('secret-token');

      final headers = mediaAuthHeaders(
        mockClient,
        'https://other.example.com/_matrix/media/v3/download/abc',
      );

      expect(headers, isNull);
    });

    test('returns null when port differs', () {
      when(mockClient.homeserver)
          .thenReturn(Uri.parse('https://matrix.example.com:8448'));
      when(mockClient.accessToken).thenReturn('secret-token');

      final headers = mediaAuthHeaders(
        mockClient,
        'https://matrix.example.com:443/_matrix/media/v3/download/abc',
      );

      expect(headers, isNull);
    });

    test('returns null when homeserver is null', () {
      when(mockClient.homeserver).thenReturn(null);

      final headers = mediaAuthHeaders(
        mockClient,
        'https://matrix.example.com/_matrix/media/v3/download/abc',
      );

      expect(headers, isNull);
    });

    test('returns null on malformed URL without throwing', () {
      when(mockClient.homeserver)
          .thenReturn(Uri.parse('https://matrix.example.com'));

      final headers = mediaAuthHeaders(mockClient, ':::not-a-url');

      expect(headers, isNull);
    });

    test('matches when both use explicit port', () {
      when(mockClient.homeserver)
          .thenReturn(Uri.parse('https://matrix.example.com:8448'));
      when(mockClient.accessToken).thenReturn('tok');

      final headers = mediaAuthHeaders(
        mockClient,
        'https://matrix.example.com:8448/_matrix/media/v3/download/abc',
      );

      expect(headers, {'authorization': 'Bearer tok'});
    });
  });
}

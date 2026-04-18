import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/log_scrubber.dart';

void main() {
  group('scrubSensitive', () {
    test('top-level sensitive keys scrubbed', () {
      final result = scrubSensitive({'token': 'abc', 'user': 'alice'});
      expect(result, {'token': '***', 'user': 'alice'});
    });

    test('nested map scrubbed', () {
      final result = scrubSensitive({
        'auth': {'password': 'p', 'type': 'x'},
      });
      expect(result, {
        'auth': {'password': '***', 'type': 'x'},
      });
    });

    test('list of maps recursed', () {
      final result = scrubSensitive([
        {'token': 't'},
        {'token': 'u'},
      ]);
      expect(result, [
        {'token': '***'},
        {'token': '***'},
      ]);
    });

    test('unrelated keys preserved', () {
      final input = {
        'foo': 'bar',
        'baz': 42,
        'qux': [1, 2, 3],
      };
      expect(scrubSensitive(input), input);
    });

    test('case-insensitive match', () {
      final result = scrubSensitive({'Token': 'x', 'PASSWORD': 'y'});
      expect(result, {'Token': '***', 'PASSWORD': '***'});
    });

    test('all six sensitive keys hit individually', () {
      for (final key in [
        'token',
        'access_token',
        'refresh_token',
        'nonce',
        'password',
        'mac',
      ]) {
        final result = scrubSensitive({key: 'secret'})! as Map;
        expect(result[key], '***', reason: 'key=$key should be scrubbed');
      }
    });

    test('empty map returns empty map', () {
      expect(scrubSensitive(<String, dynamic>{}), isEmpty);
    });

    test('non-map top-level returned unchanged', () {
      expect(scrubSensitive('hello'), 'hello');
      expect(scrubSensitive(42), 42);
      expect(scrubSensitive(null), null);
      expect(scrubSensitive(true), true);
    });

    test('deep nesting — three levels scrubbed', () {
      final result = scrubSensitive({
        'outer': {
          'middle': [
            {'token': 'deep'},
          ],
        },
      });
      expect(result, {
        'outer': {
          'middle': [
            {'token': '***'},
          ],
        },
      });
    });

    test('input map not mutated', () {
      final input = {'token': 'keep-me', 'user': 'alice'};
      scrubSensitive(input);
      expect(input['token'], 'keep-me');
    });

    test('exact match — substring not scrubbed', () {
      final result = scrubSensitive({
        'passwordless': true,
        'my_token_count': 3,
        'tokenizer': 'bpe',
      });
      expect(result, {
        'passwordless': true,
        'my_token_count': 3,
        'tokenizer': 'bpe',
      });
    });

    test('null value on sensitive key preserved', () {
      final result = scrubSensitive({'token': null, 'user': 'alice'});
      expect(result, {'token': null, 'user': 'alice'});
    });

    test('non-String map keys — scrubs by stringified key', () {
      final result =
          scrubSensitive(<dynamic, dynamic>{1: 'safe', 'token': 'x'});
      expect(result, <dynamic, dynamic>{1: 'safe', 'token': '***'});
    });
  });
}

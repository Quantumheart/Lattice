const _sensitiveKeys = <String>{
  'token',
  'access_token',
  'refresh_token',
  'nonce',
  'password',
  'mac',
};

const _redacted = '***';

/// Returns a deep copy of [input] with any value under a sensitive key
/// replaced by `'***'`. Walks nested maps and lists. Primitives and
/// non-collection objects pass through unchanged. Input is not mutated.
///
/// Key match is exact (not substring) after `toString().toLowerCase()`.
/// Null values on sensitive keys are preserved as null.
///
/// No cycle detection — callers must not pass self-referential structures.
Object? scrubSensitive(Object? input) {
  if (input is Map) {
    final out = <dynamic, dynamic>{};
    input.forEach((key, value) {
      final normalised = key.toString().toLowerCase();
      if (_sensitiveKeys.contains(normalised)) {
        out[key] = value == null ? null : _redacted;
      } else {
        out[key] = scrubSensitive(value);
      }
    });
    return out;
  }
  if (input is List) {
    return input.map(scrubSensitive).toList();
  }
  return input;
}

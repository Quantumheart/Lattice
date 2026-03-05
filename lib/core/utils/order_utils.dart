/// Lexicographic order string utilities for Matrix `m.space.child` ordering.
///
/// Order strings use printable ASCII (0x20 – 0x7E) and are at most 50 chars.
/// See: https://spec.matrix.org/latest/client-server-api/#spaces
library;

import 'package:matrix/matrix.dart';

const int _minChar = 0x20;
const int _maxChar = 0x7E;
const int _maxLength = 50;

Map<String, String> buildOrderMap(Room space) {
  final map = <String, String>{};
  for (final child in space.spaceChildren) {
    final cid = child.roomId;
    if (cid != null && child.order.isNotEmpty) {
      map[cid] = child.order;
    }
  }
  return map;
}

String? midpoint(String? before, String? after) {
  if (before != null && before.isEmpty) before = null;
  if (after != null && after.isEmpty) after = null;

  if (before == null && after == null) {
    return String.fromCharCode((_minChar + _maxChar) ~/ 2);
  }

  if (before == null) return _generateBefore(after!);
  if (after == null) return _appendAfter(before);
  return _midpointBetween(before, after);
}

String? _generateBefore(String upper) {
  for (var i = 0; i < upper.length && i < _maxLength; i++) {
    final c = upper.codeUnitAt(i);
    if (c > _minChar) {
      final mid = (_minChar + c) ~/ 2;
      return upper.substring(0, i) + String.fromCharCode(mid);
    }
  }
  return null;
}

String? _midpointBetween(String lo, String hi) {
  if (lo.isNotEmpty && hi.isNotEmpty && lo.compareTo(hi) >= 0) return null;

  final buf = StringBuffer();

  for (var i = 0; i < _maxLength; i++) {
    final loC = i < lo.length ? lo.codeUnitAt(i) : _minChar;
    final hiC = i < hi.length ? hi.codeUnitAt(i) : _maxChar;

    if (loC == hiC) {
      buf.writeCharCode(loC);
      continue;
    }

    if (hiC - loC > 1) {
      buf.writeCharCode((loC + hiC) ~/ 2);
      return buf.toString();
    }

    buf.writeCharCode(loC);
    final remaining = i + 1 < lo.length ? lo.substring(i + 1) : '';
    final suffix = _appendAfter(remaining);
    if (suffix != null && buf.length + suffix.length <= _maxLength) {
      buf.write(suffix);
      return buf.toString();
    }
  }

  return null;
}

String? _appendAfter(String s) {
  if (s.isEmpty) {
    return String.fromCharCode((_minChar + _maxChar) ~/ 2);
  }

  for (var i = s.length - 1; i >= 0; i--) {
    final c = s.codeUnitAt(i);
    if (c < _maxChar) {
      return s.substring(0, i) + String.fromCharCode((c + _maxChar + 1) ~/ 2);
    }
  }

  if (s.length < _maxLength) {
    return s + String.fromCharCode((_minChar + _maxChar) ~/ 2);
  }

  return null;
}

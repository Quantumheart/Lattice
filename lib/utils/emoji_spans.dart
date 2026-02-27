import 'package:flutter/material.dart';

/// Fallback font families for rendering color emoji on desktop platforms.
const emojiFontFallback = [
  'Noto Color Emoji',
  'Apple Color Emoji',
  'Segoe UI Emoji',
];

/// Regex matching common emoji characters and sequences (ZWJ, skin tones,
/// variation selectors). Uses Unicode ranges rather than `\p{Emoji}` which
/// is not supported by Dart's RegExp engine.
final _emojiRegex = RegExp(
  // Core emoji ranges + variation selector + ZWJ sequences + skin tone modifiers.
  r'(?:[\u{231A}-\u{23F3}\u{25AA}-\u{25FE}\u{2600}-\u{27BF}\u{2934}-\u{2935}\u{2B05}-\u{2B55}\u{3030}\u{303D}\u{1F000}-\u{1FAFF}]'
  r'[\uFE0E\uFE0F]?'
  r'(?:\u200D[\u{231A}-\u{23F3}\u{25AA}-\u{25FE}\u{2600}-\u{27BF}\u{2934}-\u{2935}\u{2B05}-\u{2B55}\u{3030}\u{303D}\u{1F000}-\u{1FAFF}][\uFE0E\uFE0F]?)*'
  r'[\u{1F3FB}-\u{1F3FF}]?)',
  unicode: true,
);

/// Splits [text] into [TextSpan]s, applying [emojiFontFallback] only to
/// emoji runs so that regular text keeps its normal font metrics.
List<TextSpan> buildEmojiSpans(String text, TextStyle? style) {
  final matches = _emojiRegex.allMatches(text).toList();
  if (matches.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }

  final emojiStyle = style?.copyWith(fontFamilyFallback: emojiFontFallback);
  final spans = <TextSpan>[];
  var lastEnd = 0;

  for (final m in matches) {
    if (m.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, m.start), style: style));
    }
    spans.add(TextSpan(text: m.group(0), style: emojiStyle));
    lastEnd = m.end;
  }

  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd), style: style));
  }

  return spans;
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A text widget that detects URLs and renders them as tappable, styled links.
class LinkableText extends StatelessWidget {
  const LinkableText({
    super.key,
    required this.text,
    required this.style,
    required this.isMe,
  });

  final String text;
  final TextStyle? style;
  final bool isMe;

  static final _urlRegex = RegExp(
    r'https?://[^\s)<>]+',
    caseSensitive: false,
  );

  /// Strip common trailing punctuation that's unlikely part of the URL.
  static String _cleanUrl(String raw) {
    // Remove trailing punctuation that's almost never part of a URL.
    while (raw.isNotEmpty && '.,;:!?\'"'.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: style);
    }

    final linkColor = isMe
        ? cs.onPrimary.withValues(alpha: 0.85)
        : cs.primary;

    final spans = <InlineSpan>[];
    var lastEnd = 0;

    for (final match in matches) {
      final rawUrl = match.group(0)!;
      final cleanedUrl = _cleanUrl(rawUrl);
      // Adjust match end to account for stripped punctuation.
      final urlEnd = match.start + cleanedUrl.length;

      // Plain text before this URL.
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: style,
        ));
      }

      // URL span.
      spans.add(TextSpan(
        text: cleanedUrl,
        style: style?.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            final uri = Uri.tryParse(cleanedUrl);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
      ));

      lastEnd = urlEnd;
    }

    // Remaining plain text after the last URL.
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: style,
      ));
    }

    return Text.rich(TextSpan(children: spans));
  }
}

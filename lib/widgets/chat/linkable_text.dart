import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/emoji_spans.dart';

/// A text widget that detects URLs and renders them as tappable, styled links.
class LinkableText extends StatelessWidget {
  const LinkableText({
    super.key,
    required this.text,
    required this.style,
    required this.isMe,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final bool isMe;

  /// Optional maximum number of lines before truncating.
  final int? maxLines;

  /// How to handle text overflow (defaults to clip).
  final TextOverflow? overflow;

  static final urlRegex = RegExp(
    r'https?://[^\s)<>]+',
    caseSensitive: false,
  );

  /// Strip common trailing punctuation that's unlikely part of the URL.
  static String cleanUrl(String raw) {
    // Remove trailing punctuation that's almost never part of a URL.
    while (raw.isNotEmpty && '.,;:!?\'"'.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final matches = urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text.rich(
        TextSpan(children: buildEmojiSpans(text, style)),
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.clip,
      );
    }

    final linkColor = isMe
        ? cs.onPrimary.withValues(alpha: 0.85)
        : cs.primary;

    final spans = <InlineSpan>[];
    var lastEnd = 0;

    for (final match in matches) {
      final rawUrl = match.group(0)!;
      final cleanedUrl = cleanUrl(rawUrl);
      // Adjust match end to account for stripped punctuation.
      final urlEnd = match.start + cleanedUrl.length;

      // Plain text before this URL.
      if (match.start > lastEnd) {
        spans.addAll(
            buildEmojiSpans(text.substring(lastEnd, match.start), style));
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
      spans.addAll(buildEmojiSpans(text.substring(lastEnd), style));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:url_launcher/url_launcher.dart';

import 'code_block.dart';
import 'linkable_text.dart';

/// Renders Matrix HTML `formatted_body` as a styled [Text.rich] widget.
///
/// Supported tags: b, strong, i, em, s, del, strike, u, ins, code, pre,
/// br, p, h1–h6, blockquote, ol, ul, li, a[href], mx-reply (stripped).
/// Unsupported tags degrade gracefully — text content is preserved.
class HtmlMessageText extends StatelessWidget {
  const HtmlMessageText({
    super.key,
    required this.html,
    required this.style,
    required this.isMe,
  });

  final String html;
  final TextStyle? style;
  final bool isMe;

  static final _mxReplyRegex = RegExp(
    r'<mx-reply>.*?</mx-reply>',
    dotAll: true,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final linkColor = isMe
        ? cs.onPrimary.withValues(alpha: 0.85)
        : cs.primary;

    // Strip mx-reply blocks before parsing.
    final cleaned = html.replaceAll(_mxReplyRegex, '');
    final document = html_parser.parseFragment(cleaned);

    final spans = <InlineSpan>[];
    for (final node in document.nodes) {
      _buildSpans(node, style ?? const TextStyle(), linkColor, spans);
    }

    // Trim leading/trailing newlines.
    _trimNewlines(spans);

    return Text.rich(TextSpan(children: spans));
  }

  void _buildSpans(
    dom.Node node,
    TextStyle currentStyle,
    Color linkColor,
    List<InlineSpan> spans,
  ) {
    if (node is dom.Text) {
      _addTextWithLinks(node.text, currentStyle, linkColor, spans);
      return;
    }

    if (node is! dom.Element) return;

    final tag = node.localName?.toLowerCase() ?? '';

    // Strip mx-reply entirely (belt-and-suspenders for DOM-level).
    if (tag == 'mx-reply') return;

    switch (tag) {
      case 'br':
        spans.add(const TextSpan(text: '\n'));
        return;

      case 'p':
        if (spans.isNotEmpty) {
          spans.add(const TextSpan(text: '\n\n'));
        }
        for (final child in node.nodes) {
          _buildSpans(child, currentStyle, linkColor, spans);
        }
        return;

      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        if (spans.isNotEmpty) {
          spans.add(const TextSpan(text: '\n\n'));
        }
        final level = int.parse(tag.substring(1));
        final scale = 1.0 + (7 - level) * 0.1; // h1=1.6, h2=1.5, ..., h6=1.1
        final headingStyle = currentStyle.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: (currentStyle.fontSize ?? 14) * scale,
        );
        for (final child in node.nodes) {
          _buildSpans(child, headingStyle, linkColor, spans);
        }
        return;

      case 'blockquote':
        if (spans.isNotEmpty) {
          spans.add(const TextSpan(text: '\n'));
        }
        final quoteSpans = <InlineSpan>[];
        final quoteStyle = currentStyle.copyWith(fontStyle: FontStyle.italic);
        for (final child in node.nodes) {
          _buildSpans(child, quoteStyle, linkColor, quoteSpans);
        }
        _trimNewlines(quoteSpans);
        spans.add(WidgetSpan(
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: linkColor,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 8),
            child: Text.rich(TextSpan(children: quoteSpans)),
          ),
        ));
        return;

      case 'ol':
      case 'ul':
        if (spans.isNotEmpty) {
          spans.add(const TextSpan(text: '\n'));
        }
        var index = 1;
        for (final child in node.nodes) {
          if (child is dom.Element && child.localName == 'li') {
            final prefix = tag == 'ol' ? '${index++}. ' : '• ';
            spans.add(TextSpan(text: prefix, style: currentStyle));
            for (final liChild in child.nodes) {
              _buildSpans(liChild, currentStyle, linkColor, spans);
            }
            spans.add(const TextSpan(text: '\n'));
          }
        }
        return;

      case 'b':
      case 'strong':
        final bold = currentStyle.copyWith(fontWeight: FontWeight.bold);
        for (final child in node.nodes) {
          _buildSpans(child, bold, linkColor, spans);
        }
        return;

      case 'i':
      case 'em':
        final italic = currentStyle.copyWith(fontStyle: FontStyle.italic);
        for (final child in node.nodes) {
          _buildSpans(child, italic, linkColor, spans);
        }
        return;

      case 's':
      case 'del':
      case 'strike':
        final strike = currentStyle.copyWith(
          decoration: TextDecoration.lineThrough,
        );
        for (final child in node.nodes) {
          _buildSpans(child, strike, linkColor, spans);
        }
        return;

      case 'u':
      case 'ins':
        final underline = currentStyle.copyWith(
          decoration: TextDecoration.underline,
        );
        for (final child in node.nodes) {
          _buildSpans(child, underline, linkColor, spans);
        }
        return;

      case 'pre':
        if (spans.isNotEmpty) {
          spans.add(const TextSpan(text: '\n'));
        }
        String? language;
        String codeText = node.text;
        for (final child in node.nodes) {
          if (child is dom.Element && child.localName == 'code') {
            final cls = child.attributes['class'] ?? '';
            final langMatch = RegExp(r'language-(\w+)').firstMatch(cls);
            language = langMatch?.group(1);
            codeText = child.text;
            break;
          }
        }
        spans.add(WidgetSpan(
          child: CodeBlock(code: codeText, language: language, isMe: isMe),
        ));
        return;

      case 'code':
        final bgColor = isMe
            ? Colors.black.withValues(alpha: 0.15)
            : currentStyle.color?.withValues(alpha: 0.08) ??
                Colors.grey.withValues(alpha: 0.08);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              node.text,
              style: currentStyle.copyWith(
                fontFamily: 'monospace',
                fontSize: (currentStyle.fontSize ?? 14) * 0.9,
              ),
            ),
          ),
        ));
        return;

      case 'a':
        final href = node.attributes['href'];
        if (href != null && href.isNotEmpty) {
          final aStyle = currentStyle.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          );
          final text = node.text;
          spans.add(TextSpan(
            text: text,
            style: aStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                final uri = Uri.tryParse(href);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
          ));
          return;
        }
        // No href — just render children.
        for (final child in node.nodes) {
          _buildSpans(child, currentStyle, linkColor, spans);
        }
        return;

      default:
        // Unsupported tag — just render children (text content preserved).
        for (final child in node.nodes) {
          _buildSpans(child, currentStyle, linkColor, spans);
        }
    }
  }

  /// Adds text with auto-linked URLs, reusing [LinkableText]'s regex.
  void _addTextWithLinks(
    String text,
    TextStyle currentStyle,
    Color linkColor,
    List<InlineSpan> spans,
  ) {
    final matches = LinkableText.urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      spans.add(TextSpan(text: text, style: currentStyle));
      return;
    }

    var lastEnd = 0;
    for (final match in matches) {
      final rawUrl = match.group(0)!;
      final cleanedUrl = LinkableText.cleanUrl(rawUrl);
      final urlEnd = match.start + cleanedUrl.length;

      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: currentStyle,
        ));
      }

      spans.add(TextSpan(
        text: cleanedUrl,
        style: currentStyle.copyWith(
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

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: currentStyle,
      ));
    }
  }

  /// Trim leading and trailing newline-only TextSpans.
  void _trimNewlines(List<InlineSpan> spans) {
    while (spans.isNotEmpty) {
      final first = spans.first;
      if (first is TextSpan && first.text != null) {
        final trimmed = first.text!.replaceAll(RegExp(r'^\n+'), '');
        if (trimmed.isEmpty) {
          spans.removeAt(0);
        } else if (trimmed != first.text) {
          spans[0] = TextSpan(text: trimmed, style: first.style);
          break;
        } else {
          break;
        }
      } else {
        break;
      }
    }
    while (spans.isNotEmpty) {
      final last = spans.last;
      if (last is TextSpan && last.text != null) {
        final trimmed = last.text!.replaceAll(RegExp(r'\n+$'), '');
        if (trimmed.isEmpty) {
          spans.removeLast();
        } else if (trimmed != last.text) {
          spans[spans.length - 1] = TextSpan(text: trimmed, style: last.style);
          break;
        } else {
          break;
        }
      } else {
        break;
      }
    }
  }
}

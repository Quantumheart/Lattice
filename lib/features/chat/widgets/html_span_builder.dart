import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:kohera/features/chat/widgets/code_block.dart';
import 'package:kohera/features/chat/widgets/linkable_span_builder.dart';
import 'package:kohera/shared/widgets/mxc_image.dart';
import 'package:matrix/matrix.dart';

class HtmlSpanBuilder {
  HtmlSpanBuilder({
    required this.isMe,
    required this.client,
    required this.linkBuilder,
  });

  final bool isMe;
  final Client? client;
  final LinkableSpanBuilder linkBuilder;

  void buildSpans(
    dom.Node node,
    TextStyle currentStyle,
    Color linkColor,
    List<InlineSpan> spans,
  ) {
    if (node is dom.Text) {
      linkBuilder.addTextWithLinks(node.text, currentStyle, linkColor, spans);
      return;
    }

    if (node is! dom.Element) return;

    final tag = node.localName?.toLowerCase() ?? '';

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
          buildSpans(child, currentStyle, linkColor, spans);
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
        final scale = 1.0 + (7 - level) * 0.1;
        final headingStyle = currentStyle.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: (currentStyle.fontSize ?? 14) * scale,
        );
        for (final child in node.nodes) {
          buildSpans(child, headingStyle, linkColor, spans);
        }
        return;

      case 'blockquote':
        if (spans.isNotEmpty) {
          spans.add(const TextSpan(text: '\n'));
        }
        final quoteSpans = <InlineSpan>[];
        final quoteStyle = currentStyle.copyWith(fontStyle: FontStyle.italic);
        for (final child in node.nodes) {
          buildSpans(child, quoteStyle, linkColor, quoteSpans);
        }
        trimNewlines(quoteSpans);
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
        ),);
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
              buildSpans(liChild, currentStyle, linkColor, spans);
            }
            spans.add(const TextSpan(text: '\n'));
          }
        }
        return;

      case 'b':
      case 'strong':
        final bold = currentStyle.copyWith(fontWeight: FontWeight.bold);
        for (final child in node.nodes) {
          buildSpans(child, bold, linkColor, spans);
        }
        return;

      case 'i':
      case 'em':
        final italic = currentStyle.copyWith(fontStyle: FontStyle.italic);
        for (final child in node.nodes) {
          buildSpans(child, italic, linkColor, spans);
        }
        return;

      case 's':
      case 'del':
      case 'strike':
        final strike = currentStyle.copyWith(
          decoration: TextDecoration.lineThrough,
        );
        for (final child in node.nodes) {
          buildSpans(child, strike, linkColor, spans);
        }
        return;

      case 'u':
      case 'ins':
        final underline = currentStyle.copyWith(
          decoration: TextDecoration.underline,
        );
        for (final child in node.nodes) {
          buildSpans(child, underline, linkColor, spans);
        }
        return;

      case 'pre':
        if (spans.isNotEmpty) {
          spans.add(const TextSpan(text: '\n'));
        }
        String? language;
        var codeText = node.text;
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
        ),);
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
        ),);
        return;

      case 'a':
        linkBuilder.addAnchor(
          node, currentStyle, linkColor, spans,
          buildSpans: buildSpans,
        );
        return;

      case 'img':
        _buildImage(node, currentStyle, spans);
        return;

      default:
        for (final child in node.nodes) {
          buildSpans(child, currentStyle, linkColor, spans);
        }
    }
  }

  void _buildImage(
    dom.Element node,
    TextStyle currentStyle,
    List<InlineSpan> spans,
  ) {
    final src = node.attributes['src'] ?? '';
    final alt = node.attributes['alt'] ?? '';
    final isCustomEmoji = node.attributes.containsKey('data-mx-emoticon');

    if (src.isEmpty) {
      if (alt.isNotEmpty) {
        spans.add(TextSpan(text: alt, style: currentStyle));
      }
      return;
    }

    if (isCustomEmoji) {
      final emojiSize = (currentStyle.fontSize ?? 14) * 1.4;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: MxcImage(
          mxcUrl: src,
          client: client,
          width: emojiSize,
          height: emojiSize,
          fallbackText: alt.isNotEmpty ? alt : ':emoji:',
          fallbackStyle: currentStyle,
        ),
      ),);
    } else {
      spans.add(WidgetSpan(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 256, maxHeight: 256),
              child: MxcImage(
                mxcUrl: src,
                client: client,
                fallbackText: alt.isNotEmpty ? alt : '[image]',
                fallbackStyle: currentStyle,
              ),
            ),
          ),
        ),
      ),);
    }
  }

  static void trimNewlines(List<InlineSpan> spans) {
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

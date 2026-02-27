import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/emoji_spans.dart';
import '../../utils/media_auth.dart';
import 'code_block.dart';
import 'linkable_text.dart';
import 'mention_pill.dart';

/// Renders Matrix HTML `formatted_body` as a styled [Text.rich] widget.
///
/// Supported tags: b, strong, i, em, s, del, strike, u, ins, code, pre,
/// br, p, h1–h6, blockquote, ol, ul, li, a[href], mx-reply (stripped).
/// Unsupported tags degrade gracefully — text content is preserved.
class HtmlMessageText extends StatefulWidget {
  const HtmlMessageText({
    super.key,
    required this.html,
    required this.style,
    required this.isMe,
    this.room,
    this.maxLines,
    this.overflow,
  });

  final String html;
  final TextStyle? style;
  final bool isMe;

  /// The room this message belongs to, used for resolving mention display names.
  final Room? room;

  /// Optional maximum number of lines before truncating.
  final int? maxLines;

  /// How to handle text overflow (defaults to clip).
  final TextOverflow? overflow;

  @override
  State<HtmlMessageText> createState() => _HtmlMessageTextState();
}

class _HtmlMessageTextState extends State<HtmlMessageText> {
  static final _matrixToRegex = RegExp(
    r'^https://matrix\.to/#/([^?]+)',
  );

  static final _mxReplyRegex = RegExp(
    r'<mx-reply>.*?</mx-reply>',
    dotAll: true,
  );

  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _createRecognizer(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    // Dispose previous recognizers before rebuilding.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final cs = Theme.of(context).colorScheme;
    final linkColor = widget.isMe
        ? cs.onPrimary.withValues(alpha: 0.85)
        : cs.primary;

    // Strip mx-reply blocks before parsing.
    final cleaned = widget.html.replaceAll(_mxReplyRegex, '');
    final document = html_parser.parseFragment(cleaned);

    final spans = <InlineSpan>[];
    for (final node in document.nodes) {
      _buildSpans(node, widget.style ?? const TextStyle(), linkColor, spans);
    }

    // Trim leading/trailing newlines.
    _trimNewlines(spans);

    return Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
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
          child: CodeBlock(code: codeText, language: language, isMe: widget.isMe),
        ));
        return;

      case 'code':
        final bgColor = widget.isMe
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
          // Check for matrix.to mention links.
          final mentionMatch = _matrixToRegex.firstMatch(href);
          if (mentionMatch != null) {
            final identifier =
                Uri.decodeComponent(mentionMatch.group(1)!);
            final pill = _buildMentionPill(identifier, currentStyle);
            if (pill != null) {
              spans.add(WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: pill,
              ));
              return;
            }
          }

          final aStyle = currentStyle.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          );
          final text = node.text;
          spans.add(TextSpan(
            text: text,
            style: aStyle,
            recognizer: _createRecognizer(() {
              final uri = Uri.tryParse(href);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }),
          ));
          return;
        }
        // No href — just render children.
        for (final child in node.nodes) {
          _buildSpans(child, currentStyle, linkColor, spans);
        }
        return;

      case 'img':
        final src = node.attributes['src'] ?? '';
        final alt = node.attributes['alt'] ?? '';
        final isCustomEmoji =
            node.attributes.containsKey('data-mx-emoticon');

        if (src.isEmpty) {
          if (alt.isNotEmpty) {
            spans.add(TextSpan(text: alt, style: currentStyle));
          }
          return;
        }

        final client = widget.room?.client;

        if (isCustomEmoji) {
          final emojiSize = (currentStyle.fontSize ?? 14) * 1.4;
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _MxcImage(
              mxcUrl: src,
              client: client,
              width: emojiSize,
              height: emojiSize,
              fallbackText: alt.isNotEmpty ? alt : ':emoji:',
              fallbackStyle: currentStyle,
            ),
          ));
        } else {
          spans.add(WidgetSpan(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 256, maxHeight: 256),
                  child: _MxcImage(
                    mxcUrl: src,
                    client: client,
                    fallbackText: alt.isNotEmpty ? alt : '[image]',
                    fallbackStyle: currentStyle,
                  ),
                ),
              ),
            ),
          ));
        }
        return;

      default:
        // Unsupported tag — just render children (text content preserved).
        for (final child in node.nodes) {
          _buildSpans(child, currentStyle, linkColor, spans);
        }
    }
  }

  /// Builds a [MentionPill] for a Matrix identifier, or returns null if
  /// the identifier is not a recognized mention format.
  Widget? _buildMentionPill(String identifier, TextStyle currentStyle) {
    if (identifier.startsWith('@')) {
      // User mention.
      final displayName = widget.room
              ?.unsafeGetUserFromMemoryOrFallback(identifier)
              .displayName ??
          identifier;
      return MentionPill(
        displayName: displayName,
        matrixId: identifier,
        type: MentionType.user,
        isMe: widget.isMe,
        style: currentStyle,
      );
    } else if (identifier.startsWith('!') || identifier.startsWith('#')) {
      // Room mention (room ID or alias).
      const type = MentionType.room;
      String displayName;
      if (identifier.startsWith('#')) {
        // Alias — show it directly (without the leading #, MentionPill adds it).
        displayName = identifier.substring(1);
      } else {
        // Room ID — try to resolve a local display name.
        final resolved = widget.room?.client.getRoomById(identifier);
        displayName =
            resolved?.getLocalizedDisplayname() ?? identifier;
      }
      return MentionPill(
        displayName: displayName,
        matrixId: identifier,
        type: type,
        isMe: widget.isMe,
        style: currentStyle,
      );
    }
    return null;
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
      spans.addAll(buildEmojiSpans(text, currentStyle));
      return;
    }

    var lastEnd = 0;
    for (final match in matches) {
      final rawUrl = match.group(0)!;
      final cleanedUrl = LinkableText.cleanUrl(rawUrl);
      final urlEnd = match.start + cleanedUrl.length;

      if (match.start > lastEnd) {
        spans.addAll(
            buildEmojiSpans(text.substring(lastEnd, match.start), currentStyle));
      }

      spans.add(TextSpan(
        text: cleanedUrl,
        style: currentStyle.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
        recognizer: _createRecognizer(() {
          final uri = Uri.tryParse(cleanedUrl);
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }),
      ));

      lastEnd = urlEnd;
    }

    if (lastEnd < text.length) {
      spans.addAll(buildEmojiSpans(text.substring(lastEnd), currentStyle));
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

// ── MXC image loader ─────────────────────────────────────────

/// Resolves an mxc:// URI asynchronously and displays the image.
class _MxcImage extends StatefulWidget {
  const _MxcImage({
    required this.mxcUrl,
    required this.client,
    this.width,
    this.height,
    required this.fallbackText,
    required this.fallbackStyle,
  });

  final String mxcUrl;
  final Client? client;
  final double? width;
  final double? height;
  final String fallbackText;
  final TextStyle? fallbackStyle;

  @override
  State<_MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<_MxcImage> {
  String? _resolvedUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_MxcImage old) {
    super.didUpdateWidget(old);
    if (old.mxcUrl != widget.mxcUrl) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final src = widget.mxcUrl;
    final client = widget.client;

    if (!src.startsWith('mxc://') || client == null) {
      // Not an mxc URI — use directly (e.g. https://).
      if (mounted) {
        setState(() {
          _resolvedUrl = src.startsWith('http') ? src : null;
          _loading = false;
        });
      }
      return;
    }

    final mxc = Uri.tryParse(src);
    if (mxc == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final useThumb = widget.width != null && widget.width! <= 96;
      final Uri uri;
      if (useThumb) {
        uri = await mxc.getThumbnailUri(
          client,
          width: 48,
          height: 48,
          method: ThumbnailMethod.scale,
        );
      } else {
        uri = await mxc.getDownloadUri(client);
      }
      if (mounted) {
        setState(() {
          _resolvedUrl = uri.toString();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Lattice] Failed to resolve mxc image: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
      );
    }

    if (_resolvedUrl == null) {
      return Text(widget.fallbackText, style: widget.fallbackStyle);
    }

    return Image.network(
      _resolvedUrl!,
      width: widget.width,
      height: widget.height,
      headers: widget.client != null
          ? mediaAuthHeaders(widget.client!, _resolvedUrl!)
          : null,
      errorBuilder: (_, __, ___) =>
          Text(widget.fallbackText, style: widget.fallbackStyle),
    );
  }
}

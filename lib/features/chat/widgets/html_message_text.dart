import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:kohera/features/chat/widgets/html_span_builder.dart';
import 'package:kohera/features/chat/widgets/linkable_span_builder.dart';
import 'package:matrix/matrix.dart';

class HtmlMessageText extends StatefulWidget {
  const HtmlMessageText({
    required this.html, required this.style, required this.isMe, super.key,
    this.room,
    this.maxLines,
    this.overflow,
  });

  final String html;
  final TextStyle? style;
  final bool isMe;
  final Room? room;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<HtmlMessageText> createState() => _HtmlMessageTextState();
}

class _HtmlMessageTextState extends State<HtmlMessageText> {
  static final _mxReplyRegex = RegExp(
    '<mx-reply>.*?</mx-reply>',
    dotAll: true,
  );

  final _recognizers = <TapGestureRecognizer>[];

  List<InlineSpan>? _cachedSpans;
  String? _cachedHtml;
  TextStyle? _cachedStyle;
  Color? _cachedLinkColor;

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
    final cs = Theme.of(context).colorScheme;
    final linkColor = widget.isMe
        ? cs.onPrimary.withValues(alpha: 0.85)
        : cs.primary;

    if (_cachedSpans == null ||
        _cachedHtml != widget.html ||
        _cachedStyle != widget.style ||
        _cachedLinkColor != linkColor) {
      for (final r in _recognizers) {
        r.dispose();
      }
      _recognizers.clear();

      final linkBuilder = LinkableSpanBuilder(
        room: widget.room,
        isMe: widget.isMe,
        createRecognizer: _createRecognizer,
      );
      final spanBuilder = HtmlSpanBuilder(
        isMe: widget.isMe,
        client: widget.room?.client,
        linkBuilder: linkBuilder,
      );

      final cleaned = widget.html.replaceAll(_mxReplyRegex, '');
      final document = html_parser.parseFragment(cleaned);

      final spans = <InlineSpan>[];
      for (final node in document.nodes) {
        spanBuilder.buildSpans(
          node, widget.style ?? const TextStyle(), linkColor, spans,
        );
      }
      HtmlSpanBuilder.trimNewlines(spans);

      _cachedSpans = spans;
      _cachedHtml = widget.html;
      _cachedStyle = widget.style;
      _cachedLinkColor = linkColor;
    }

    return Text.rich(
      TextSpan(children: _cachedSpans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/widgets/inline_image_preview.dart';
import 'package:kohera/features/chat/widgets/link_preview_card.dart';
import 'package:kohera/features/chat/widgets/linkable_text.dart';
import 'package:provider/provider.dart';

class MessageBubbleLinkPreview extends StatefulWidget {
  const MessageBubbleLinkPreview({
    required this.bodyText,
    required this.isMe,
    super.key,
  });

  final String bodyText;
  final bool isMe;

  @override
  State<MessageBubbleLinkPreview> createState() =>
      _MessageBubbleLinkPreviewState();
}

String? extractFirstPreviewUrl(String body) {
  for (final match in LinkableText.urlRegex.allMatches(body)) {
    final url = LinkableText.cleanUrl(match.group(0)!);
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host != 'matrix.to') return url;
  }
  return null;
}

bool isDirectImageUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  return path.endsWith('.gif') ||
      path.endsWith('.png') ||
      path.endsWith('.jpg') ||
      path.endsWith('.jpeg') ||
      path.endsWith('.webp');
}

class _MessageBubbleLinkPreviewState extends State<MessageBubbleLinkPreview> {
  String? _cachedPreviewUrl;
  String? _previewUrlBody;

  @override
  Widget build(BuildContext context) {
    final enabled = context
        .select<PreferencesService, bool>((p) => p.showLinkPreviews);
    if (!enabled) return const SizedBox.shrink();
    if (_previewUrlBody != widget.bodyText) {
      _previewUrlBody = widget.bodyText;
      _cachedPreviewUrl = extractFirstPreviewUrl(widget.bodyText);
    }
    final url = _cachedPreviewUrl;
    if (url == null) return const SizedBox.shrink();
    if (isDirectImageUrl(url)) {
      return InlineImagePreview(url: url, isMe: widget.isMe);
    }
    return LinkPreviewCard(url: url, isMe: widget.isMe);
  }
}

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../utils/text_highlight.dart';
import '../utils/time_format.dart';
import 'user_avatar.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.event,
    required this.query,
    required this.onTap,
  });

  final Event event;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final senderName =
        event.senderFromMemoryOrFallback.displayName ?? event.senderId;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender avatar
            UserAvatar(
              client: event.room.client,
              avatarUrl: event.senderFromMemoryOrFallback.avatarUrl,
              userId: event.senderId,
              size: 36,
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name + timestamp
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        formatRelativeTimestamp(event.originServerTs),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),

                  // Message body with highlighted query
                  _buildHighlightedBody(tt, cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedBody(TextTheme tt, ColorScheme cs) {
    final body = event.body;
    final spans = highlightSpans(body, query);

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: tt.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        children: spans.map((span) {
          if (span.isMatch) {
            return TextSpan(
              text: span.text,
              style: TextStyle(
                backgroundColor: cs.primaryContainer,
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            );
          }
          return TextSpan(text: span.text);
        }).toList(),
      ),
    );
  }
}

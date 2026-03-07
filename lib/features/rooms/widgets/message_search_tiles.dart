import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/utils/text_highlight.dart';
import 'package:lattice/core/utils/time_format.dart';
import 'package:lattice/features/rooms/services/room_list_search_controller.dart';
import 'package:lattice/features/rooms/widgets/room_list_models.dart';

// ── Message search header ────────────────────────────────────
class MessageSearchHeader extends StatelessWidget {
  const MessageSearchHeader({required this.item, super.key});
  final MessageSearchHeaderItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.resultCount != null
                      ? 'MESSAGES (${item.resultCount})'
                      : 'MESSAGES',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (item.isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (item.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.error!,
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Message search result tile ───────────────────────────────
class MessageSearchResultTile extends StatelessWidget {
  const MessageSearchResultTile({
    required this.result, required this.query, super.key,
  });

  final MessageSearchResult result;
  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final spans = highlightSpans(result.body, query.trim());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          mouseCursor: SystemMouseCursors.click,
          onTap: () => context.goNamed(
            Routes.room,
            pathParameters: {'roomId': result.roomId},
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Room name
                Text(
                  result.roomName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                // Sender + timestamp
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        result.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      formatRelativeTimestamp(result.originServerTs),
                      style: tt.bodySmall?.copyWith(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Body with highlights
                RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: spans.map((s) {
                      return TextSpan(
                        text: s.text,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          backgroundColor: s.isMatch
                              ? cs.primaryContainer
                              : null,
                          fontWeight:
                              s.isMatch ? FontWeight.w600 : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Load more button ─────────────────────────────────────────
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({
    required this.isLoading, required this.onPressed, super.key,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : TextButton(
                onPressed: onPressed,
                child: const Text('Load more messages'),
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'reply_preview_banner.dart';

class ComposeBar extends StatelessWidget {
  const ComposeBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.replyEvent,
    required this.onCancelReply,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final Event? replyEvent;
  final VoidCallback onCancelReply;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 0,
        bottom: MediaQuery.paddingOf(context).bottom + 8,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyEvent != null)
            ReplyPreviewBanner(
              event: replyEvent!,
              onCancel: onCancelReply,
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.add_rounded, color: cs.onSurfaceVariant),
                  onPressed: () {
                    // TODO: attachment picker
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: 'Type a message…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor:
                          cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    ),
                    minLines: 1,
                    maxLines: 5,
                  ),
                ),
                const SizedBox(width: 4),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    return IconButton.filled(
                      onPressed: hasText ? onSend : null,
                      icon: const Icon(Icons.send_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            hasText ? cs.primary : cs.surfaceContainerHighest,
                        foregroundColor:
                            hasText ? cs.onPrimary : cs.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

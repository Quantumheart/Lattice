import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kohera/features/chat/widgets/hover_action_bar.dart';

class MessageBubbleHoverBarSlot extends StatelessWidget {
  const MessageBubbleHoverBarSlot({
    required this.enabled,
    required this.hovering,
    required this.onMore,
    required this.onQuickReactOpenChanged,
    this.onReact,
    this.onQuickReact,
    this.onReply,
    super.key,
  });

  final bool enabled;
  final ValueListenable<bool> hovering;
  final VoidCallback? onReact;
  final void Function(String emoji)? onQuickReact;
  final VoidCallback? onReply;
  final void Function(Offset position) onMore;
  final ValueChanged<bool> onQuickReactOpenChanged;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: hovering,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return HoverActionBar(
          cs: Theme.of(context).colorScheme,
          onReact: onReact,
          onQuickReact: onQuickReact,
          onReply: onReply,
          onMore: onMore,
          onQuickReactOpenChanged: onQuickReactOpenChanged,
        );
      },
    );
  }
}

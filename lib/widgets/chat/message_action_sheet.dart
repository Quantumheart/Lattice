import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'message_bubble.dart';

// ── Data class ──────────────────────────────────────────

class MessageAction {
  const MessageAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

// ── Public entry point ──────────────────────────────────

void showMessageActionSheet({
  required BuildContext context,
  required Event event,
  required bool isMe,
  required Rect bubbleRect,
  required List<MessageAction> actions,
  required Timeline? timeline,
}) {
  Navigator.of(context).push(
    _MessageActionSheetRoute(
      event: event,
      isMe: isMe,
      bubbleRect: bubbleRect,
      actions: actions,
      timeline: timeline,
      capturedTheme: Theme.of(context),
    ),
  );
}

// ── Route ───────────────────────────────────────────────

class _MessageActionSheetRoute extends PopupRoute<void> {
  _MessageActionSheetRoute({
    required this.event,
    required this.isMe,
    required this.bubbleRect,
    required this.actions,
    required this.timeline,
    required this.capturedTheme,
  });

  final Event event;
  final bool isMe;
  final Rect bubbleRect;
  final List<MessageAction> actions;
  final Timeline? timeline;
  final ThemeData capturedTheme;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _MessageActionSheet(
      event: event,
      isMe: isMe,
      bubbleRect: bubbleRect,
      actions: actions,
      timeline: timeline,
      animation: animation,
      capturedTheme: capturedTheme,
    );
  }
}

// ── Overlay layout ──────────────────────────────────────

class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({
    required this.event,
    required this.isMe,
    required this.bubbleRect,
    required this.actions,
    required this.timeline,
    required this.animation,
    required this.capturedTheme,
  });

  final Event event;
  final bool isMe;
  final Rect bubbleRect;
  final List<MessageAction> actions;
  final Timeline? timeline;
  final Animation<double> animation;
  final ThemeData capturedTheme;

  static const _actionListWidth = 220.0;
  static const _actionRowHeight = 48.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;
    final screenWidth = mq.size.width;
    final safeTop = mq.padding.top + 8;
    final safeBottom = mq.padding.bottom + 8;

    final actionListHeight = actions.length * _actionRowHeight;

    // Total height needed: bubble + gap + action list
    final totalHeight = bubbleRect.height + _gap + actionListHeight;

    // Determine top position: try to keep bubble in place, but shift up if
    // the action list would overflow the screen bottom.
    double bubbleTop = bubbleRect.top;
    final bottomEdge = bubbleTop + totalHeight;
    if (bottomEdge > screenHeight - safeBottom) {
      bubbleTop = screenHeight - safeBottom - totalHeight;
    }
    if (bubbleTop < safeTop) {
      bubbleTop = safeTop;
    }

    final actionListTop = bubbleTop + bubbleRect.height + _gap;

    // Horizontal alignment: align action list with the bubble's leading edge
    double actionListLeft;
    if (isMe) {
      // Right-aligned: align action list's right edge with bubble's right edge
      actionListLeft = bubbleRect.right - _actionListWidth;
    } else {
      actionListLeft = bubbleRect.left;
    }
    // Clamp within screen
    actionListLeft = clampDouble(actionListLeft, 8, screenWidth - _actionListWidth - 8);

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    return Stack(
      children: [
        // ── Bubble preview ──────────────────────────────
        Positioned(
          top: bubbleTop,
          left: bubbleRect.left,
          width: bubbleRect.width,
          height: bubbleRect.height,
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
              child: IgnorePointer(
                child: AbsorbPointer(
                  child: Theme(
                    data: capturedTheme,
                    child: Material(
                      type: MaterialType.transparency,
                      child: MessageBubble(
                        event: event,
                        isMe: isMe,
                        isFirst: true,
                        timeline: timeline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Action list ─────────────────────────────────
        Positioned(
          top: actionListTop,
          left: actionListLeft,
          width: _actionListWidth,
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: _ActionList(actions: actions),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Action list widget ──────────────────────────────────

class _ActionList extends StatelessWidget {
  const _ActionList({required this.actions});

  final List<MessageAction> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: cs.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < actions.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            _ActionRow(action: actions[i]),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final MessageAction action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        action.onTap();
      },
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  action.label,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                ),
              ),
              Icon(action.icon, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

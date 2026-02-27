import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Displays "Alice is typing…" with an animated dot indicator.
///
/// Placed between the message list and the compose bar in chat view.
/// Listens to [syncStream] manually and only rebuilds when the set of
/// typing user IDs actually changes.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    super.key,
    required this.room,
    required this.myUserId,
    required this.syncStream,
  });

  final Room room;
  final String? myUserId;

  /// Stream that triggers checks (typically [client.onSync.stream]).
  final Stream<dynamic> syncStream;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();

  /// Format a list of typing users into a human-readable string.
  ///
  /// Exposed as a static method so it can be reused (e.g. room list preview).
  static String formatTypers(List<User> typers) {
    final names = typers.map((u) => u.displayName ?? u.id).toList();
    return switch (names.length) {
      1 => '${names[0]} is typing',
      2 => '${names[0]} and ${names[1]} are typing',
      3 => '${names[0]}, ${names[1]}, and ${names[2]} are typing',
      _ => '${names[0]}, ${names[1]}, and ${names.length - 2} others are typing',
    };
  }
}

class _TypingIndicatorState extends State<TypingIndicator> {
  StreamSubscription<dynamic>? _sub;
  List<String> _typerIds = const [];

  @override
  void initState() {
    super.initState();
    _sub = widget.syncStream.listen((_) => _checkTypers());
    _checkTypers();
  }

  @override
  void didUpdateWidget(TypingIndicator old) {
    super.didUpdateWidget(old);
    if (old.syncStream != widget.syncStream) {
      _sub?.cancel();
      _sub = widget.syncStream.listen((_) => _checkTypers());
    }
    if (old.room != widget.room || old.myUserId != widget.myUserId) {
      _checkTypers();
    }
  }

  void _checkTypers() {
    final ids = widget.room.typingUsers
        .where((u) => u.id != widget.myUserId)
        .map((u) => u.id)
        .toList();
    if (!listEquals(ids, _typerIds)) {
      setState(() => _typerIds = ids);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typers = widget.room.typingUsers
        .where((u) => u.id != widget.myUserId)
        .toList();

    if (typers.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            const _AnimatedDots(),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                TypingIndicator.formatTypers(typers),
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three small dots that animate in sequence.
class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots();

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger each dot by 0.2 of the animation cycle.
            final delay = i * 0.2;
            final t = (_ctrl.value - delay) % 1.0;
            // Dot bounces in the first half of its cycle.
            final offset = t < 0.5 ? -3.0 * (1 - (2 * t - 1).abs()) : 0.0;
            return Transform.translate(
              offset: Offset(0, offset),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

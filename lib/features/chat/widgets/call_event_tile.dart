import 'package:flutter/material.dart';
import 'package:lattice/core/utils/time_format.dart';
import 'package:lattice/features/calling/models/call_constants.dart';
import 'package:matrix/matrix.dart';

class CallEventTile extends StatelessWidget {
  const CallEventTile({
    required this.event,
    required this.isMe,
    this.onTap,
    this.duration,
    super.key,
  });

  final Event event;
  final bool isMe;
  final VoidCallback? onTap;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final (icon, text) = _resolve();

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMe) const SizedBox(width: 40),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMessageTime(event.originServerTs),
                    style: tt.bodySmall?.copyWith(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (isMe) const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  (IconData, String) _resolve() {
    final sender = event.senderFromMemoryOrFallback.calcDisplayname();

    switch (event.type) {
      case kCallInvite:
        return (Icons.call_rounded, '$sender started a call');

      case kCallHangup:
        final reason = event.content.tryGet<String>('reason');
        if (reason == 'invite_timeout') {
          return (Icons.call_missed_rounded, 'Missed call from $sender');
        }
        final label = duration != null
            ? 'Call ended \u2014 ${_formatDuration(duration!)}'
            : 'Call ended';
        return (Icons.call_end_rounded, label);

      case kCallReject:
        return (Icons.call_end_rounded, '$sender declined the call');

      case kCallAnswer:
        return (Icons.call_rounded, '$sender answered the call');

      default:
        return (Icons.call_rounded, 'Call event');
    }
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

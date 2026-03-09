import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class CallEventTile extends StatelessWidget {
  const CallEventTile({required this.event, this.onTap, super.key});

  final Event event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final (icon, text) = _resolve();

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, String) _resolve() {
    final sender = event.senderFromMemoryOrFallback.calcDisplayname();

    switch (event.type) {
      case 'm.call.invite':
        return (Icons.call_rounded, '$sender started a call');

      case 'm.call.hangup':
        final reason = event.content.tryGet<String>('reason');
        if (reason == 'invite_timeout') {
          return (Icons.call_missed_rounded, 'Missed call from $sender');
        }
        return (Icons.call_end_rounded, 'Call ended');

      case 'm.call.reject':
        return (Icons.call_end_rounded, '$sender declined the call');

      default:
        return (Icons.call_rounded, 'Call event');
    }
  }
}

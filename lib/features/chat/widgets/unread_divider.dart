import 'package:flutter/material.dart';

class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 1, color: cs.primary.withValues(alpha: 0.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'New messages',
              style: tt.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Container(height: 1, color: cs.primary.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

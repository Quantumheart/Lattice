import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class VerificationRequestTile extends StatelessWidget {
  const VerificationRequestTile({required this.event, super.key});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_user_outlined, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Requested verification',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

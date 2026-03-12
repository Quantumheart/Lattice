import 'package:flutter/material.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:matrix/matrix.dart';

// coverage:ignore-start

class JoinCallBanner extends StatelessWidget {
  const JoinCallBanner({required this.room, required this.callService, super.key});

  final Room room;
  final CallService callService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final callIds = callService.activeCallIdsForRoom(room.id);
    final participantCount = callIds.isNotEmpty
        ? callService.callParticipantCount(room.id, callIds.first)
        : 0;

    return Material(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.call_rounded, size: 18, color: cs.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Call in progress${participantCount > 0 ? ' \u2014 $participantCount participant${participantCount == 1 ? '' : 's'}' : ''}',
                style: TextStyle(color: cs.onPrimaryContainer),
              ),
            ),
            FilledButton.tonal(
              onPressed: () => CallNavigator.startCall(
                context,
                roomId: room.id,
              ),
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}
// coverage:ignore-end

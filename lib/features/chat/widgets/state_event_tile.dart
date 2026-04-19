import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class StateEventTile extends StatelessWidget {
  const StateEventTile({required this.event, super.key});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final (icon, text) = _resolve();
    final isTombstone = event.type == EventTypes.RoomTombstone;

    Widget content = Container(
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
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
    );

    if (isTombstone) {
      content = InkWell(
        onTap: () => _onTombstoneTap(context),
        borderRadius: BorderRadius.circular(16),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [content],
      ),
    );
  }

  Future<void> _onTombstoneTap(BuildContext context) async {
    final replacement =
        event.content.tryGet<String>('replacement_room');
    if (replacement == null || replacement.isEmpty) return;

    final matrix = context.read<MatrixService>();
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    try {
      final existing = matrix.client.getRoomById(replacement);
      if (existing == null) {
        await matrix.client.joinRoom(replacement);
      }
      router.goNamed(Routes.room, pathParameters: {'roomId': replacement});
    } catch (e) {
      debugPrint('[Kohera] Failed to open replacement room: $e');
      scaffold.showSnackBar(
        const SnackBar(content: Text('Could not open the upgraded room')),
      );
    }
  }

  (IconData, String) _resolve() {
    final sender = event.senderFromMemoryOrFallback.calcDisplayname();

    switch (event.type) {
      case EventTypes.RoomMember:
        return _resolveMember(sender);

      case EventTypes.RoomName:
        final name = event.content.tryGet<String>('name') ?? '';
        return (
          Icons.edit_outlined,
          name.isEmpty
              ? '$sender removed the room name'
              : "$sender changed the room name to '$name'",
        );

      case EventTypes.RoomTopic:
        final topic = event.content.tryGet<String>('topic') ?? '';
        return (
          Icons.edit_outlined,
          topic.isEmpty
              ? '$sender removed the room topic'
              : "$sender changed the topic to '$topic'",
        );

      case EventTypes.RoomAvatar:
        return (Icons.image_outlined, '$sender changed the room avatar');

      case EventTypes.RoomTombstone:
        final body = event.content.tryGet<String>('body');
        final suffix = (body != null && body.isNotEmpty) ? ' $body' : '';
        return (
          Icons.upgrade_rounded,
          'This room has been upgraded.$suffix Tap to open the new room.',
        );

      default:
        return (Icons.info_outline, 'Room updated');
    }
  }

  (IconData, String) _resolveMember(String sender) {
    final membership = event.content.tryGet<String>('membership');
    final prevMembership = event.prevContent?.tryGet<String>('membership');
    final target = event.stateKey;
    final targetUser = target != null
        ? event.room.unsafeGetUserFromMemoryOrFallback(target)
        : null;
    final targetName = targetUser?.calcDisplayname() ?? target ?? 'Someone';
    final reason = event.content.tryGet<String>('reason');

    switch (membership) {
      case 'invite':
        return (
          Icons.person_add_alt_1_outlined,
          '$targetName was invited by $sender',
        );
      case 'join':
        if (prevMembership == 'join') {
          final prevDisplay = event.prevContent?.tryGet<String>('displayname');
          final newDisplay = event.content.tryGet<String>('displayname');
          if (prevDisplay != newDisplay) {
            return (
              Icons.badge_outlined,
              newDisplay == null || newDisplay.isEmpty
                  ? '$targetName removed their display name'
                  : "$targetName changed their display name to '$newDisplay'",
            );
          }
          final prevAvatar = event.prevContent?.tryGet<String>('avatar_url');
          final newAvatar = event.content.tryGet<String>('avatar_url');
          if (prevAvatar != newAvatar) {
            return (
              Icons.image_outlined,
              '$targetName changed their avatar',
            );
          }
          return (Icons.login_rounded, '$targetName updated their profile');
        }
        return (Icons.login_rounded, '$targetName joined');
      case 'leave':
        if (target == event.senderId) {
          if (prevMembership == 'invite') {
            return (
              Icons.cancel_outlined,
              '$targetName rejected the invitation',
            );
          }
          return (Icons.logout_rounded, '$targetName left');
        }
        final reasonSuffix =
            (reason != null && reason.isNotEmpty) ? ' ($reason)' : '';
        return (
          Icons.person_remove_outlined,
          '$targetName was kicked by $sender$reasonSuffix',
        );
      case 'ban':
        final reasonSuffix =
            (reason != null && reason.isNotEmpty) ? ' ($reason)' : '';
        return (
          Icons.block_rounded,
          '$targetName was banned by $sender$reasonSuffix',
        );
      case 'knock':
        return (
          Icons.front_hand_outlined,
          '$targetName requested to join',
        );
      default:
        return (Icons.info_outline, 'Membership changed');
    }
  }
}

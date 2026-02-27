import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    show DefaultEmojiTextStyle;
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../user_avatar.dart';

// ── ReactionChips ────────────────────────────────────────────

/// Displays aggregated emoji reaction chips below a message bubble.
///
/// Each chip shows the emoji and its count. Chips where the current user
/// has reacted are highlighted. Tapping toggles the reaction; long-pressing
/// opens a bottom sheet listing who reacted.
class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.event,
    required this.timeline,
    required this.client,
    required this.isMe,
    required this.senderAvatarOffset,
    this.onToggle,
  });

  final Event event;
  final Timeline timeline;
  final Client client;
  final bool isMe;
  final double senderAvatarOffset;
  final void Function(String emoji)? onToggle;

  @override
  Widget build(BuildContext context) {
    final reactionEvents =
        event.aggregatedEvents(timeline, RelationshipTypes.reaction);
    if (reactionEvents.isEmpty) return const SizedBox.shrink();

    // Group by emoji key.
    final grouped = <String, List<Event>>{};
    for (final re in reactionEvents) {
      final key = re.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key != null) {
        (grouped[key] ??= []).add(re);
      }
    }
    if (grouped.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final myId = client.userID;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) SizedBox(width: senderAvatarOffset),
          Flexible(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: grouped.entries.map((entry) {
                final emoji = entry.key;
                final events = entry.value;
                final isMine =
                    events.any((e) => e.senderId == myId);

                return GestureDetector(
                  onTap: () => onToggle?.call(emoji),
                  onLongPress: () => showReactorsSheet(
                    context,
                    emoji,
                    events,
                    event.room,
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isMine
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: isMine
                          ? Border.all(color: cs.primary, width: 1)
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          emoji,
                          style: DefaultEmojiTextStyle.copyWith(fontSize: 16),
                        ),
                        if (events.length > 1) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${events.length}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isMine
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reactors bottom sheet ────────────────────────────────────

/// Shows a modal bottom sheet listing all users who sent a given reaction.
void showReactorsSheet(
  BuildContext context,
  String emoji,
  List<Event> reactionEvents,
  Room room,
) {
  showModalBottomSheet(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '$emoji ${reactionEvents.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: reactionEvents.length,
                itemBuilder: (context, i) {
                  final re = reactionEvents[i];
                  final user =
                      room.unsafeGetUserFromMemoryOrFallback(re.senderId);
                  final name = user.displayName ?? re.senderId;

                  return ListTile(
                    leading: UserAvatar(
                      client: room.client,
                      avatarUrl: user.avatarUrl,
                      userId: re.senderId,
                      size: 36,
                    ),
                    title: Text(name),
                    subtitle: name != re.senderId ? Text(re.senderId) : null,
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

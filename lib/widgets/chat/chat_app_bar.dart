import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../room_avatar.dart';
import '../room_details_panel.dart';
import 'pinned_messages_sheet.dart';

/// Default app bar for the chat screen showing room name, avatar, and actions.
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    super.key,
    required this.room,
    this.onBack,
    this.onShowDetails,
    required this.onSearch,
    this.onPinnedEvent,
  });

  final Room room;
  final VoidCallback? onBack;
  final VoidCallback? onShowDetails;
  final VoidCallback onSearch;
  final void Function(Event event)? onPinnedEvent;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return AppBar(
      leading: onBack != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
            )
          : null,
      automaticallyImplyLeading: false,
      titleSpacing: onBack != null ? 0 : 16,
      title: Row(
        children: [
          RoomAvatarWidget(room: room, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.getLocalizedDisplayname(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium,
                ),
                Text(
                  _memberCountLabel(room),
                  style: tt.bodyMedium?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (room.pinnedEventIds.isNotEmpty && onPinnedEvent != null)
          Builder(
            builder: (buttonContext) => IconButton(
              icon: Badge.count(
                count: room.pinnedEventIds.length,
                child: const Icon(Icons.push_pin_rounded),
              ),
              tooltip: 'Pinned messages',
              onPressed: () => showPinnedMessagesPopup(
                buttonContext,
                room,
                onTap: onPinnedEvent!,
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.search_rounded),
          onPressed: onSearch,
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: () {
            if (onShowDetails != null) {
              onShowDetails!();
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RoomDetailsPanel(
                    roomId: room.id,
                    isFullPage: true,
                  ),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  static String _memberCountLabel(Room room) {
    final count = room.summary.mJoinedMemberCount ?? 0;
    if (count == 0) return '';
    if (count == 1) return '1 member';
    return '$count members';
  }
}

/// Search-mode app bar with a text field and clear button.
class ChatSearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatSearchAppBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: onClose,
      ),
      titleSpacing: 0,
      title: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: tt.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search messages…',
          border: InputBorder.none,
          hintStyle: tt.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      actions: [
        if (controller.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              controller.clear();
              onChanged('');
              focusNode.requestFocus();
            },
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/models/incoming_call_info.dart' as model;
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/chat/widgets/pinned_messages_popup.dart';
import 'package:lattice/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    required this.room, required this.onSearch, super.key,
    this.onBack,
    this.onShowDetails,
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
      title: LayoutBuilder(
        builder: (context, constraints) {
          final showAvatar = constraints.maxWidth > 100;
          return Row(
            children: [
              if (showAvatar) ...[
                RoomAvatarWidget(room: room, size: 34),
                const SizedBox(width: 12),
              ],
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
          );
        },
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
        _CallButton(room: room),
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
              context.goNamed(
                Routes.roomDetails,
                pathParameters: {'roomId': room.id},
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

class _CallButton extends StatefulWidget {
  const _CallButton({required this.room});

  final Room room;

  @override
  State<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<_CallButton> {
  bool _starting = false;

  Future<void> _startCall(model.CallType type) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await CallNavigator.startCall(
        context,
        roomId: widget.room.id,
        type: type,
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final callState = callService.callState;
    final roomHasCall = callService.roomHasActiveCall(widget.room.id);
    final isInCall = callService.activeCallRoomId == widget.room.id;
    final busy = _starting || (callState != LatticeCallState.idle && !roomHasCall);

    if (roomHasCall && !isInCall) {
      return TextButton.icon(
        icon: const Icon(Icons.call_rounded),
        label: const Text('Join'),
        style: TextButton.styleFrom(foregroundColor: Colors.green),
        onPressed: busy ? null : () => _startCall(model.CallType.voice),
      );
    }

    if (isInCall) {
      return PopupMenuButton<String>(
        icon: Icon(Icons.call_rounded, color: Colors.green.shade400),
        tooltip: 'In call',
        onSelected: (value) {
          if (value == 'go') {
            context.goNamed(
              Routes.call,
              pathParameters: {'roomId': widget.room.id},
            );
          } else if (value == 'leave') {
            unawaited(CallNavigator.endCall(context));
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'go',
            child: ListTile(
              leading: Icon(Icons.open_in_new_rounded),
              title: Text('Go to call'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'leave',
            child: ListTile(
              leading: Icon(Icons.call_end_rounded, color: Colors.red),
              title: Text('Leave call'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      );
    }

    return PopupMenuButton<model.CallType>(
      icon: const Icon(Icons.call_rounded),
      tooltip: 'Call',
      enabled: !busy,
      onSelected: _startCall,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: model.CallType.voice,
          child: ListTile(
            leading: Icon(Icons.call_rounded),
            title: Text('Voice call'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: model.CallType.video,
          child: ListTile(
            leading: Icon(Icons.videocam_rounded),
            title: Text('Video call'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class ChatSearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatSearchAppBar({
    required this.controller, required this.focusNode, required this.onChanged, required this.onClose, super.key,
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';

import '../services/matrix_service.dart';
import '../widgets/room_avatar.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.roomId,
    this.onBack,
  });

  final String roomId;

  /// On narrow layouts, called to pop back to room list.
  final VoidCallback? onBack;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timeline? _timeline;
  StreamSubscription? _timelineSub;
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    _initTimeline();
    _scrollCtrl.addListener(_onScroll);
  }

  Future<void> _initTimeline() async {
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    _timeline = await room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingHistory) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_timeline == null || !_timeline!.canRequestHistory || _loadingHistory) {
      return;
    }
    _loadingHistory = true;
    try {
      await _timeline!.requestHistory();
    } finally {
      _loadingHistory = false;
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    await room.sendTextEvent(text);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _timelineSub?.cancel();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (room == null) {
      return Scaffold(
        body: Center(child: Text('Room not found', style: tt.bodyLarge)),
      );
    }

    final events = _timeline?.events
            .where((e) =>
                e.type == EventTypes.Message ||
                e.type == EventTypes.Encrypted)
            .toList() ??
        [];

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              )
            : null,
        automaticallyImplyLeading: false,
        titleSpacing: widget.onBack != null ? 0 : 16,
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
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              // TODO: in-room search
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {
              // TODO: room details sheet
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Messages ──
          Expanded(
            child: _timeline == null
                ? const Center(child: CircularProgressIndicator())
                : events.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet.\nSay hello!',
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: events.length,
                        itemBuilder: (context, i) {
                          final event = events[i];
                          final isMe =
                              event.senderId == matrix.client.userID;

                          // Group consecutive messages from same sender.
                          final prevSender = i + 1 < events.length
                              ? events[i + 1].senderId
                              : null;
                          final isFirst = event.senderId != prevSender;

                          return MessageBubble(
                            event: event,
                            isMe: isMe,
                            isFirst: isFirst,
                          );
                        },
                      ),
          ),

          // ── Compose bar ──
          _ComposeBar(
            controller: _msgCtrl,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  String _memberCountLabel(Room room) {
    final count = room.summary.mJoinedMemberCount ?? 0;
    if (count == 0) return '';
    if (count == 1) return '1 member';
    return '$count members';
  }
}

class _ComposeBar extends StatelessWidget {
  const _ComposeBar({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 8,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: cs.onSurfaceVariant),
            onPressed: () {
              // TODO: attachment picker
            },
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
              minLines: 1,
              maxLines: 5,
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            onPressed: onSend,
            icon: const Icon(Icons.send_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/upload_state.dart';
import '../services/chat_search_controller.dart';
import '../services/matrix_service.dart';
import '../services/typing_controller.dart';
import '../widgets/chat/chat_app_bar.dart';
import '../widgets/chat/compose_bar.dart';
import '../widgets/chat/delete_event_dialog.dart';
import '../widgets/chat/emoji_picker_sheet.dart';
import '../widgets/chat/file_send_handler.dart';
import '../widgets/chat/long_press_wrapper.dart';
import '../widgets/chat/message_action_sheet.dart';
import '../widgets/chat/message_bubble.dart' show MessageBubble, stripReplyFallback;
import '../widgets/chat/reaction_chips.dart';
import '../widgets/chat/read_receipts.dart';
import '../widgets/chat/search_results_body.dart';
import '../widgets/chat/swipeable_message.dart';
import '../widgets/chat/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.roomId,
    this.onBack,
    this.onShowDetails,
  });

  final String roomId;

  /// On narrow layouts, called to pop back to room list.
  final VoidCallback? onBack;

  /// On desktop, called to toggle the room details side panel.
  final VoidCallback? onShowDetails;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _historyLoadThreshold = 3;
  static const _scrollAnimationDuration = Duration(milliseconds: 400);
  static const _readMarkerDelay = Duration(seconds: 1);

  final _msgCtrl = TextEditingController();
  final _itemScrollCtrl = ItemScrollController();
  final _itemPosListener = ItemPositionsListener.create();
  Timeline? _timeline;
  bool _loadingHistory = false;
  Timer? _readMarkerTimer;
  int _initGeneration = 0;
  List<Event>? _cachedVisibleEvents;

  // ── Reply state ─────────────────────────────────────────
  final _replyNotifier = ValueNotifier<Event?>(null);

  // ── Edit state ──────────────────────────────────────────
  final _editNotifier = ValueNotifier<Event?>(null);

  // ── Upload state ────────────────────────────────────────
  final _uploadNotifier = ValueNotifier<UploadState?>(null);

  // ── Typing ─────────────────────────────────────────────
  TypingController? _typingCtrl;

  // ── Search ─────────────────────────────────────────────
  late ChatSearchController _search;
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _search = _createSearchController();
    _initTimeline();
    _itemPosListener.itemPositions.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.roomId != widget.roomId) {
      _timeline?.cancelSubscriptions();
      _readMarkerTimer?.cancel();
      _replyNotifier.value = null;
      _editNotifier.value = null;
      _msgCtrl.clear();
      _cachedVisibleEvents = null;
      _typingCtrl?.dispose();
      _search.removeListener(_onSearchChanged);
      _search.dispose();
      _search = _createSearchController();
      _initTimeline();
    }
  }

  ChatSearchController _createSearchController() {
    return ChatSearchController(
      roomId: widget.roomId,
      getRoom: () => context.read<MatrixService>().client.getRoomById(widget.roomId),
    )..addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  // ── Timeline ───────────────────────────────────────────

  Future<void> _initTimeline() async {
    final gen = ++_initGeneration;
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    _typingCtrl = TypingController(room: room);

    _timeline = await room.getTimeline(
      onUpdate: () {
        if (mounted) {
          _cachedVisibleEvents = null;
          setState(() {});
        }
        _markAsRead(room);
      },
    );
    if (gen != _initGeneration) return;
    if (mounted) setState(() {});
    _markAsRead(room);
  }

  List<Event> get _visibleEvents {
    if (_cachedVisibleEvents != null) return _cachedVisibleEvents!;
    final events = _timeline?.events;
    if (events == null) return [];
    _cachedVisibleEvents = events
        .where((e) =>
            (e.type == EventTypes.Message || e.type == EventTypes.Encrypted) &&
            e.relationshipType != RelationshipTypes.edit)
        .toList();
    return _cachedVisibleEvents!;
  }

  void _markAsRead(Room room) {
    _readMarkerTimer?.cancel();
    _readMarkerTimer = Timer(_readMarkerDelay, () async {
      if (!mounted) return;
      final lastEvent = room.lastEvent;
      if (lastEvent != null && room.notificationCount > 0) {
        try {
          await room.setReadMarker(lastEvent.eventId, mRead: lastEvent.eventId);
        } catch (e) {
          debugPrint('[Lattice] Failed to mark as read: $e');
        }
      }
    });
  }

  void _onScroll() {
    final positions = _itemPosListener.itemPositions.value;
    if (positions.isEmpty) return;
    final maxIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    if (maxIndex >= _visibleEvents.length - _historyLoadThreshold && !_loadingHistory) {
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

  // ── Reply ──────────────────────────────────────────────

  void _setReplyTo(Event event) {
    _replyNotifier.value = event;
  }

  void _cancelReply() {
    _replyNotifier.value = null;
  }

  // ── Edit ───────────────────────────────────────────────

  void _setEditEvent(Event event) {
    _replyNotifier.value = null;
    _editNotifier.value = event;
    final displayEvent =
        _timeline != null ? event.getDisplayEvent(_timeline!) : event;
    _msgCtrl.text = stripReplyFallback(displayEvent.body);
    _msgCtrl.selection =
        TextSelection.collapsed(offset: _msgCtrl.text.length);
  }

  void _cancelEdit() {
    _editNotifier.value = null;
    _msgCtrl.clear();
  }

  // ── Reactions ──────────────────────────────────────

  Future<void> _toggleReaction(Event event, String emoji) async {
    if (_timeline == null) return;
    final matrix = context.read<MatrixService>();
    final myId = matrix.client.userID;

    // Find user's existing reaction for this emoji.
    final existing = event
        .aggregatedEvents(_timeline!, RelationshipTypes.reaction)
        .where((e) =>
            e.senderId == myId &&
            e.content
                    .tryGetMap<String, Object?>('m.relates_to')
                    ?.tryGet<String>('key') ==
                emoji)
        .firstOrNull;

    try {
      if (existing != null) {
        await existing.redactEvent();
      } else {
        await event.room.sendReaction(event.eventId, emoji);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed to react: ${MatrixService.friendlyAuthError(e)}')),
        );
      }
    }
  }

  // ── Pin ──────────────────────────────────────────────

  Future<void> _togglePin(Event event) async {
    final room = event.room;
    final pinned = List<String>.from(room.pinnedEventIds);
    final wasPinned = pinned.contains(event.eventId);
    if (wasPinned) {
      pinned.remove(event.eventId);
    } else {
      pinned.add(event.eventId);
    }
    try {
      await room.setPinnedEvents(pinned);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasPinned
                ? 'Failed to unpin message'
                : 'Failed to pin message'),
          ),
        );
      }
    }
  }

  // ── Send ───────────────────────────────────────────────

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final replyEvent = _replyNotifier.value;
    _replyNotifier.value = null;

    final editEvent = _editNotifier.value;
    _editNotifier.value = null;

    final scaffold = ScaffoldMessenger.of(context);
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    try {
      await room.sendTextEvent(
        text,
        inReplyTo: editEvent == null ? replyEvent : null,
        editEventId: editEvent?.eventId,
      );
    } catch (e) {
      _msgCtrl.text = text;
      _replyNotifier.value = replyEvent;
      _editNotifier.value = editEvent;
      scaffold.showSnackBar(
        SnackBar(content: Text('Failed to send: ${MatrixService.friendlyAuthError(e)}')),
      );
    }
  }

  // ── Search methods ────────────────────────────────────────

  void _openSearch() {
    _search.open();
    _searchCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _search.close();
    _searchCtrl.clear();
  }

  void _scrollToEvent(Event event, {bool closeSearch = true}) {
    if (closeSearch) _closeSearch();
    _navigateToEvent(event);
  }

  void _navigateToEvent(Event event) {
    final index = _visibleEvents.indexWhere((e) => e.eventId == event.eventId);
    if (index == -1) {
      debugPrint('[Lattice] Event not in loaded timeline: ${event.eventId}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message not in loaded history'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _search.setHighlight(event.eventId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemScrollCtrl.isAttached) {
        _itemScrollCtrl.scrollTo(
          index: index,
          duration: _scrollAnimationDuration,
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
  }

  @override
  void dispose() {
    _itemPosListener.itemPositions.removeListener(_onScroll);
    _msgCtrl.dispose();
    _replyNotifier.dispose();
    _editNotifier.dispose();
    _uploadNotifier.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _typingCtrl?.dispose();
    _readMarkerTimer?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    final tt = Theme.of(context).textTheme;

    if (room == null) {
      return Scaffold(
        body: Center(child: Text('Room not found', style: tt.bodyLarge)),
      );
    }

    late final PreferredSizeWidget appBar;
    if (_search.isSearching) {
      appBar = ChatSearchAppBar(
        controller: _searchCtrl,
        focusNode: _searchFocusNode,
        onChanged: _search.onQueryChanged,
        onClose: _closeSearch,
      );
    } else {
      appBar = ChatAppBar(
        room: room,
        onBack: widget.onBack,
        onShowDetails: widget.onShowDetails,
        onSearch: _openSearch,
        onPinnedEvent: _navigateToEvent,
      );
    }

    return Scaffold(
      appBar: appBar,
      body: _search.isSearching
          ? SearchResultsBody(
              search: _search,
              onTapResult: _scrollToEvent,
            )
          : _buildChatBody(matrix, room),
    );
  }

  // ── Chat body (messages + compose) ────────────────────────

  Widget _buildChatBody(MatrixService matrix, Room room) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final events = _visibleEvents;

    return Column(
      children: [
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
                  : _buildMessageList(events, matrix, room),
        ),
        TypingIndicator(
          room: room,
          myUserId: matrix.client.userID,
          syncStream: matrix.client.onSync.stream,
        ),
        ValueListenableBuilder<Event?>(
          valueListenable: _replyNotifier,
          builder: (context, replyEvent, _) {
            return ValueListenableBuilder<Event?>(
              valueListenable: _editNotifier,
              builder: (context, editEvent, _) {
                return ComposeBar(
                  controller: _msgCtrl,
                  onSend: _send,
                  replyEvent: replyEvent,
                  onCancelReply: _cancelReply,
                  editEvent: editEvent,
                  onCancelEdit: _cancelEdit,
                  onAttach: () => pickAndSendFile(context, widget.roomId, _uploadNotifier),
                  uploadNotifier: _uploadNotifier,
                  room: room,
                  joinedRooms: matrix.rooms,
                  typingController: _typingCtrl,
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildMessageList(
      List<Event> events, MatrixService matrix, Room room) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final receiptMap = buildReceiptMap(room, matrix.client.userID);
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollCtrl,
      itemPositionsListener: _itemPosListener,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, i) =>
          _buildMessageItem(events, i, matrix, isMobile, receiptMap),
    );
  }

  Widget _buildMessageItem(
      List<Event> events, int i, MatrixService matrix, bool isMobile,
      Map<String, List<Receipt>> receiptMap) {
    final event = events[i];
    final isMe = event.senderId == matrix.client.userID;

    // Group consecutive messages from same sender.
    final prevSender = i + 1 < events.length ? events[i + 1].senderId : null;
    final isFirst = event.senderId != prevSender;

    final isRedacted = event.redacted;

    final room = event.room;
    final canPin = !isRedacted &&
        room.canChangeStateEvent('m.room.pinned_events');

    final hasReactions = _timeline != null &&
        event.hasAggregatedEvents(_timeline!, RelationshipTypes.reaction);
    final receipts = receiptMap[event.eventId];

    Widget? subBubble;
    if (hasReactions || (receipts != null && receipts.isNotEmpty)) {
      subBubble = Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (hasReactions)
            ReactionChips(
              event: event,
              timeline: _timeline!,
              client: matrix.client,
              isMe: isMe,
              onToggle: (emoji) => _toggleReaction(event, emoji),
            ),
          if (receipts != null && receipts.isNotEmpty)
            ReadReceiptsRow(
              receipts: receipts,
              client: matrix.client,
              isMe: isMe,
            ),
        ],
      );
    }

    Widget content = MessageBubble(
      event: event,
      isMe: isMe,
      isFirst: isFirst,
      highlighted: event.eventId == _search.highlightedEventId,
      isPinned: room.pinnedEventIds.contains(event.eventId),
      timeline: _timeline,
      onTapReply: isRedacted ? null : _navigateToEvent,
      onReply: isRedacted ? null : () => _setReplyTo(event),
      onEdit: !isRedacted && isMe ? () => _setEditEvent(event) : null,
      onDelete: !isRedacted && event.canRedact ? () => confirmAndDeleteEvent(context, event) : null,
      onReact: isRedacted ? null : () => showEmojiPickerSheet(context, (emoji) => _toggleReaction(event, emoji)),
      onPin: canPin ? () => _togglePin(event) : null,
      subBubble: subBubble,
    );

    if (isMobile) {
      return SwipeableMessage(
        onReply: () => _setReplyTo(event),
        child: LongPressWrapper(
          onLongPress: (rect) => _showMobileActions(event, isMe, rect),
          child: content,
        ),
      );
    }
    return content;
  }

  void _showMobileActions(Event event, bool isMe, Rect bubbleRect) {
    if (event.redacted) return;

    final cs = Theme.of(context).colorScheme;
    final isPinned = event.room.pinnedEventIds.contains(event.eventId);
    final actions = <MessageAction>[
      MessageAction(
        label: 'Reply',
        icon: Icons.reply_rounded,
        onTap: () => _setReplyTo(event),
      ),
      if (isMe)
        MessageAction(
          label: 'Edit',
          icon: Icons.edit_rounded,
          onTap: () => _setEditEvent(event),
        ),
      MessageAction(
        label: 'React',
        icon: Icons.add_reaction_outlined,
        onTap: () => showEmojiPickerSheet(context, (emoji) => _toggleReaction(event, emoji)),
      ),
      if (event.room.canChangeStateEvent('m.room.pinned_events'))
        MessageAction(
          label: isPinned ? 'Unpin' : 'Pin',
          icon: isPinned
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          onTap: () => _togglePin(event),
        ),
      MessageAction(
        label: 'Copy',
        icon: Icons.copy_rounded,
        onTap: () {
          final displayEvent = _timeline != null
              ? event.getDisplayEvent(_timeline!)
              : event;
          Clipboard.setData(
            ClipboardData(text: stripReplyFallback(displayEvent.body)),
          );
        },
      ),
      if (event.canRedact)
        MessageAction(
          label: isMe ? 'Delete' : 'Remove',
          icon: Icons.delete_outline_rounded,
          onTap: () => confirmAndDeleteEvent(context, event),
          color: cs.error,
        ),
    ];

    showMessageActionSheet(
      context: context,
      event: event,
      isMe: isMe,
      bubbleRect: bubbleRect,
      actions: actions,
      timeline: _timeline,
      onQuickReact: (emoji) => _toggleReaction(event, emoji),
    );
  }
}

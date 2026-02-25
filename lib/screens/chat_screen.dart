import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../services/chat_search_controller.dart';
import '../services/matrix_service.dart';
import '../widgets/chat_app_bar.dart';
import '../widgets/compose_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/search_results_body.dart';
import '../widgets/swipeable_message.dart';

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

  // ── Reply state ─────────────────────────────────────────
  Event? _replyToEvent;

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
      _search.removeListener(_onSearchChanged);
      _search.close();
      _replyToEvent = null;
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
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    _timeline = await room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
        _markAsRead(room);
      },
    );
    if (mounted) setState(() {});
    _markAsRead(room);
  }

  List<Event>? _cachedVisibleEvents;
  int _lastTimelineLength = -1;

  List<Event> get _visibleEvents {
    final events = _timeline?.events;
    if (events == null) return [];
    if (_cachedVisibleEvents != null && events.length == _lastTimelineLength) {
      return _cachedVisibleEvents!;
    }
    _lastTimelineLength = events.length;
    _cachedVisibleEvents = events
        .where((e) =>
            e.type == EventTypes.Message || e.type == EventTypes.Encrypted)
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
    setState(() => _replyToEvent = event);
  }

  void _cancelReply() {
    setState(() => _replyToEvent = null);
  }

  // ── Send ───────────────────────────────────────────────

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final replyEvent = _replyToEvent;
    setState(() => _replyToEvent = null);

    final scaffold = ScaffoldMessenger.of(context);
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    try {
      await room.sendTextEvent(text, inReplyTo: replyEvent);
    } catch (e) {
      _msgCtrl.text = text;
      setState(() => _replyToEvent = replyEvent);
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

    final events = _visibleEvents;
    final index = events.indexWhere((e) => e.eventId == event.eventId);
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
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
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
      );
    }

    return Scaffold(
      appBar: appBar,
      body: _search.isSearching
          ? SearchResultsBody(
              search: _search,
              onTapResult: _scrollToEvent,
            )
          : _buildChatBody(matrix),
    );
  }

  // ── Chat body (messages + compose) ────────────────────────

  Widget _buildChatBody(MatrixService matrix) {
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
                  : _buildMessageList(events, matrix),
        ),
        ComposeBar(
          controller: _msgCtrl,
          onSend: _send,
          replyEvent: _replyToEvent,
          onCancelReply: _cancelReply,
        ),
      ],
    );
  }

  Widget _buildMessageList(List<Event> events, MatrixService matrix) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollCtrl,
      itemPositionsListener: _itemPosListener,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, i) {
        final event = events[i];
        final isMe = event.senderId == matrix.client.userID;

        // Group consecutive messages from same sender.
        final prevSender =
            i + 1 < events.length ? events[i + 1].senderId : null;
        final isFirst = event.senderId != prevSender;

        final bubble = MessageBubble(
          event: event,
          isMe: isMe,
          isFirst: isFirst,
          highlighted: event.eventId == _search.highlightedEventId,
          timeline: _timeline,
          onTapReply: (e) => _scrollToEvent(e, closeSearch: false),
          onReply: () => _setReplyTo(event),
        );

        if (isMobile) {
          return SwipeableMessage(
            onReply: () => _setReplyTo(event),
            child: bubble,
          );
        }
        return bubble;
      },
    );
  }
}

import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/upload_state.dart';
import '../services/chat_search_controller.dart';
import '../services/matrix_service.dart';
import '../services/typing_controller.dart';
import '../widgets/chat/typing_indicator.dart';
import '../widgets/chat/chat_app_bar.dart';
import '../widgets/chat/compose_bar.dart';
import '../widgets/chat/message_action_sheet.dart';
import '../widgets/chat/message_bubble.dart' show MessageBubble, stripReplyFallback;
import '../widgets/chat/read_receipts.dart';
import '../widgets/chat/search_results_body.dart';
import '../widgets/chat/swipeable_message.dart';

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
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    _typingCtrl?.dispose();
    _typingCtrl = TypingController(room: room);

    _timeline = await room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
        _markAsRead(room);
      },
    );
    if (mounted) setState(() {});
    _markAsRead(room);
  }

  List<Event> get _visibleEvents {
    final events = _timeline?.events;
    if (events == null) return [];
    return events
        .where((e) =>
            (e.type == EventTypes.Message || e.type == EventTypes.Encrypted) &&
            e.relationshipType != RelationshipTypes.edit)
        .toList();
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

  // ── Delete / Redact ────────────────────────────────────

  Future<void> _deleteEvent(Event event) async {
    final matrix = context.read<MatrixService>();
    final isMe = event.senderId == matrix.client.userID;
    final title = isMe ? 'Delete message?' : 'Remove message?';
    final body = isMe
        ? 'This message will be permanently deleted for everyone.'
        : 'This message will be permanently removed from the room.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(isMe ? 'Delete' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await event.room.redactEvent(event.eventId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${MatrixService.friendlyAuthError(e)}')),
        );
      }
    }
  }

  // ── Attach ─────────────────────────────────────────────

  Future<void> _pickAndSendFile() async {
    final scaffold = ScaffoldMessenger.of(context);
    final matrix = context.read<MatrixService>();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes;
    final name = picked.name;
    if (bytes == null) return;

    _uploadNotifier.value = UploadState(
      status: UploadStatus.uploading,
      fileName: name,
    );
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) {
      _uploadNotifier.value = null;
      return;
    }

    try {
      final file = MatrixFile.fromMimeType(bytes: bytes, name: name);
      await room.sendFileEvent(file);
      _uploadNotifier.value = null;
    } on FileTooBigMatrixException {
      _uploadNotifier.value = null;
      scaffold.showSnackBar(
        const SnackBar(content: Text('File too large for this server')),
      );
    } catch (e) {
      _uploadNotifier.value = UploadState(
        status: UploadStatus.error,
        fileName: name,
        error: e.toString(),
      );
      scaffold.showSnackBar(
        SnackBar(content: Text('Upload failed: ${MatrixService.friendlyAuthError(e)}')),
      );
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
                  onAttach: _pickAndSendFile,
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

    final bubble = MessageBubble(
      event: event,
      isMe: isMe,
      isFirst: isFirst,
      highlighted: event.eventId == _search.highlightedEventId,
      timeline: _timeline,
      onTapReply: isRedacted ? null : _navigateToEvent,
      onReply: isRedacted ? null : () => _setReplyTo(event),
      onEdit: !isRedacted && isMe ? () => _setEditEvent(event) : null,
      onDelete: !isRedacted && event.canRedact ? () => _deleteEvent(event) : null,
    );

    final receipts = receiptMap[event.eventId];

    Widget content;
    if (receipts != null && receipts.isNotEmpty) {
      content = Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          bubble,
          ReadReceiptsRow(
            receipts: receipts,
            client: matrix.client,
            isMe: isMe,
          ),
        ],
      );
    } else {
      content = bubble;
    }

    if (isMobile) {
      return SwipeableMessage(
        onReply: () => _setReplyTo(event),
        child: _LongPressWrapper(
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
          onTap: () => _deleteEvent(event),
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
    );
  }
}

/// Detects long press using raw pointer events so it does not participate in
/// the gesture arena and therefore does not interfere with the horizontal drag
/// recogniser in [SwipeableMessage].
class _LongPressWrapper extends StatefulWidget {
  const _LongPressWrapper({required this.onLongPress, required this.child});

  final void Function(Rect bubbleRect) onLongPress;
  final Widget child;

  @override
  State<_LongPressWrapper> createState() => _LongPressWrapperState();
}

class _LongPressWrapperState extends State<_LongPressWrapper> {
  static const _longPressDuration = Duration(milliseconds: 500);
  static const _touchSlop = 18.0;

  Timer? _timer;
  Offset? _startPosition;

  void _onPointerDown(PointerDownEvent event) {
    _startPosition = event.position;
    _timer?.cancel();
    _timer = Timer(_longPressDuration, () {
      HapticFeedback.mediumImpact();
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final topLeft = box.localToGlobal(Offset.zero);
        final rect = topLeft & box.size;
        widget.onLongPress(rect);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_startPosition != null &&
        (event.position - _startPosition!).distance > _touchSlop) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _timer?.cancel();
    _timer = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:lattice/core/models/pending_attachment.dart';
import 'package:lattice/core/models/upload_state.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/utils/reply_fallback.dart';
import 'package:lattice/features/chat/services/chat_search_controller.dart';
import 'package:lattice/features/chat/services/media_playback_service.dart';
import 'package:lattice/features/chat/services/typing_controller.dart';
import 'package:lattice/features/chat/services/voice_recording_controller.dart';
import 'package:lattice/features/chat/widgets/chat_app_bar.dart';
import 'package:lattice/features/chat/widgets/compose_bar.dart';
import 'package:lattice/features/chat/widgets/delete_event_dialog.dart';
import 'package:lattice/features/chat/widgets/drop_confirm_dialog.dart';
import 'package:lattice/features/chat/widgets/drop_send_handler.dart';
import 'package:lattice/features/chat/widgets/drop_zone_overlay.dart';
import 'package:lattice/features/chat/widgets/emoji_picker_sheet.dart';
import 'package:lattice/features/chat/widgets/file_send_handler.dart';
import 'package:lattice/features/chat/widgets/paste_image_handler.dart';
import 'package:lattice/features/chat/widgets/long_press_wrapper.dart';
import 'package:lattice/features/chat/widgets/message_action_sheet.dart';
import 'package:lattice/features/chat/widgets/message_bubble.dart' show MessageBubble;
import 'package:lattice/features/chat/widgets/reaction_chips.dart';
import 'package:lattice/features/chat/widgets/read_receipts.dart';
import 'package:lattice/features/chat/widgets/search_results_body.dart';
import 'package:lattice/features/chat/widgets/swipeable_message.dart';
import 'package:lattice/features/chat/widgets/typing_indicator.dart';
import 'package:lattice/features/chat/widgets/voice_send_handler.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.roomId, super.key,
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
  static const _historyLoadThreshold = 15;
  static const _scrollAnimationDuration = Duration(milliseconds: 400);
  static const _readMarkerDelay = Duration(seconds: 1);
  static const _maxAttachments = 10;

  final _msgCtrl = TextEditingController();
  final _composeFocusNode = FocusNode();
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

  // ── Pending attachments ────────────────────────────────
  final _pendingAttachments = ValueNotifier<List<PendingAttachment>>([]);

  // ── Typing ─────────────────────────────────────────────
  TypingController? _typingCtrl;

  // ── Voice recording ─────────────────────────────────────
  VoiceRecordingController? _voiceCtrl;

  // ── Drag-and-drop ──────────────────────────────────────
  bool _isDragging = false;
  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  // ── Search ─────────────────────────────────────────────
  late ChatSearchController _search;
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _search = _createSearchController();
    unawaited(_initTimeline());
    _itemPosListener.itemPositions.addListener(_onScroll);
    _composeFocusNode.requestFocus();
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.roomId != widget.roomId) {
      _timeline?.cancelSubscriptions();
      _readMarkerTimer?.cancel();
      _replyNotifier.value = null;
      _editNotifier.value = null;
      _pendingAttachments.value = [];
      _msgCtrl.clear();
      _cachedVisibleEvents = null;
      _typingCtrl?.dispose();
      _voiceCtrl?.dispose();
      _search.removeListener(_onSearchChanged);
      _search.dispose();
      _search = _createSearchController();
      unawaited(_initTimeline());
      _composeFocusNode.requestFocus();
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
    _voiceCtrl = VoiceRecordingController();

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
    _requestMissingKeys(room);
  }

  /// Request decryption keys from the online backup for any BadEncrypted
  /// events visible in the current timeline.
  void _requestMissingKeys(Room room) {
    final encryption = room.client.encryption;
    if (encryption == null) return;

    final events = _timeline?.events;
    if (events == null) return;

    for (final event in events) {
      if (event.type == EventTypes.Encrypted &&
          event.messageType == MessageTypes.BadEncrypted) {
        final sessionId = event.content.tryGet<String>('session_id');
        if (sessionId != null) {
          unawaited(
            encryption.keyManager.loadSingleKey(room.id, sessionId).catchError(
              (Object e) {
                debugPrint('[Lattice] Key load failed for $sessionId: $e');
              },
            ),
          );
        }
      }
    }
  }

  List<Event> get _visibleEvents {
    if (_cachedVisibleEvents != null) return _cachedVisibleEvents!;
    final events = _timeline?.events;
    if (events == null) return [];
    _cachedVisibleEvents = events
        .where((e) =>
            (e.type == EventTypes.Message || e.type == EventTypes.Encrypted) &&
            e.relationshipType != RelationshipTypes.edit,)
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
          final sendPublic = context.read<PreferencesService>().readReceipts;
          await room.setReadMarker(
            lastEvent.eventId,
            mRead: sendPublic ? lastEvent.eventId : null,
          );
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
      unawaited(_loadMore());
    }
  }

  Future<void> _loadMore() async {
    if (_timeline == null || !_timeline!.canRequestHistory || _loadingHistory) {
      return;
    }
    setState(() => _loadingHistory = true);
    try {
      // Load batches in a loop: a single server batch may contain mostly
      // state events that are filtered out of _visibleEvents, so keep
      // fetching until we have enough visible messages past the viewport
      // or the server has no more history.
      while (mounted && _timeline!.canRequestHistory) {
        await _timeline!.requestHistory();
        _cachedVisibleEvents = null;
        final positions = _itemPosListener.itemPositions.value;
        if (positions.isEmpty) break;
        final maxIndex =
            positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
        if (maxIndex < _visibleEvents.length - _historyLoadThreshold) break;
      }
    } catch (e) {
      debugPrint('[Lattice] Failed to load history: $e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // ── Reply ──────────────────────────────────────────────

  void _setReplyTo(Event event) {
    _replyNotifier.value = event;
    _composeFocusNode.requestFocus();
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
                emoji,)
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
                  'Failed to react: ${MatrixService.friendlyAuthError(e)}',),),
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
                : 'Failed to pin message',),
          ),
        );
      }
    }
  }

  // ── Voice recording ────────────────────────────────────

  Future<void> _startVoiceRecording() async {
    context.read<MediaPlaybackService>().pauseActive();
    final started = await _voiceCtrl!.startRecording();
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
    }
  }

  Future<void> _stopAndSendVoiceMessage() async {
    final elapsed = _voiceCtrl!.elapsed;
    final path = await _voiceCtrl!.stopRecording();
    if (path != null && mounted) {
      await sendVoiceMessage(
        context,
        widget.roomId,
        _uploadNotifier,
        path,
        elapsed,
      );
    }
  }

  Future<void> _cancelVoiceRecording() async {
    await _voiceCtrl?.cancelRecording();
  }

  // ── Clipboard paste ──────────────────────────────────────

  Future<void> _handlePasteImage() async {
    final imageData = await readClipboardImage();
    if (imageData == null || !mounted) return;

    final name = generatePasteFilename(imageData.mimeType);
    _addAttachment(PendingAttachment.fromBytes(bytes: imageData.bytes, name: name));
  }

  // ── Pending attachments ─────────────────────────────────

  void _addAttachment(PendingAttachment attachment) {
    if (_pendingAttachments.value.length >= _maxAttachments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum $_maxAttachments attachments allowed')),
      );
      return;
    }
    _pendingAttachments.value = [..._pendingAttachments.value, attachment];
  }

  void _removeAttachment(int index) {
    final list = [..._pendingAttachments.value];
    list.removeAt(index);
    _pendingAttachments.value = list;
  }

  void _clearAttachments() {
    _pendingAttachments.value = [];
  }

  // ── Send ───────────────────────────────────────────────

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    final attachments = List<PendingAttachment>.from(_pendingAttachments.value);
    if (text.isEmpty && attachments.isEmpty) return;

    _msgCtrl.clear();
    _pendingAttachments.value = [];

    final replyEvent = _replyNotifier.value;
    _replyNotifier.value = null;

    final editEvent = _editNotifier.value;
    _editNotifier.value = null;

    final scaffold = ScaffoldMessenger.of(context);
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    for (var i = 0; i < attachments.length; i++) {
      final ok = await sendFileBytes(
        scaffold: scaffold,
        room: room,
        name: attachments[i].name,
        bytes: attachments[i].bytes,
        uploadNotifier: _uploadNotifier,
      );
      if (!ok) {
        _pendingAttachments.value = attachments.sublist(i);
        if (text.isNotEmpty) {
          _msgCtrl.text = text;
          _replyNotifier.value = replyEvent;
          _editNotifier.value = editEvent;
        }
        return;
      }
    }

    if (text.isNotEmpty) {
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
        unawaited(
          _itemScrollCtrl.scrollTo(
            index: index,
            duration: _scrollAnimationDuration,
            curve: Curves.easeInOut,
            alignment: 0.5,
          ),
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
    _pendingAttachments.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _composeFocusNode.dispose();
    _typingCtrl?.dispose();
    _voiceCtrl?.dispose();
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

    final column = Column(
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
                return ValueListenableBuilder<List<PendingAttachment>>(
                  valueListenable: _pendingAttachments,
                  builder: (context, attachments, _) {
                    return ComposeBar(
                      controller: _msgCtrl,
                      onSend: _send,
                      replyEvent: replyEvent,
                      onCancelReply: _cancelReply,
                      editEvent: editEvent,
                      onCancelEdit: _cancelEdit,
                      onAttach: () async {
                        final attachment = await pickFileAsAttachment();
                        if (attachment != null && mounted) _addAttachment(attachment);
                      },
                      onPasteImage: _isDesktop ? _handlePasteImage : null,
                      uploadNotifier: _uploadNotifier,
                      room: room,
                      joinedRooms: matrix.rooms,
                      typingController: _typingCtrl,
                      focusNode: _composeFocusNode,
                      voiceController: _voiceCtrl,
                      onMicTap: _startVoiceRecording,
                      onVoiceStop: _stopAndSendVoiceMessage,
                      onVoiceCancel: _cancelVoiceRecording,
                      pendingAttachments: attachments,
                      onRemoveAttachment: _removeAttachment,
                      onClearAttachments: _clearAttachments,
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );

    if (!_isDesktop) return column;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        final files = details.files;
        if (files.isEmpty || !mounted) return;
        for (final file in files) {
          final bytes = await file.readAsBytes();
          if (!mounted) return;
          _addAttachment(PendingAttachment.fromBytes(bytes: bytes, name: file.name));
        }
      },
      child: Stack(
        children: [
          column,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _isDragging ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: DropZoneOverlay(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
      List<Event> events, MatrixService matrix, Room room,) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final showReceipts = context.watch<PreferencesService>().readReceipts;
    final receiptMap = showReceipts
        ? buildReceiptMap(room, matrix.client.userID)
        : <String, List<Receipt>>{};
    final hasLoadingIndicator = _loadingHistory;
    final totalCount = events.length + (hasLoadingIndicator ? 1 : 0);
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollCtrl,
      itemPositionsListener: _itemPosListener,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: totalCount,
      itemBuilder: (context, i) {
        if (hasLoadingIndicator && i == totalCount - 1) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _buildMessageItem(events, i, matrix, isMobile, receiptMap);
      },
    );
  }

  Widget _buildMessageItem(
      List<Event> events, int i, MatrixService matrix, bool isMobile,
      Map<String, List<Receipt>> receiptMap,) {
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
    final receipts = receiptMap[event.eventId]
        ?.where((r) => r.user.id != event.senderId)
        .toList();

    Widget? reactionBubble;
    if (hasReactions) {
      reactionBubble = ReactionChips(
        event: event,
        timeline: _timeline!,
        client: matrix.client,
        isMe: isMe,
        onToggle: (emoji) => _toggleReaction(event, emoji),
      );
    }

    Widget? subBubble;
    if (receipts != null && receipts.isNotEmpty) {
      subBubble = ReadReceiptsRow(
        receipts: receipts,
        client: matrix.client,
        isMe: isMe,
      );
    }

    final Widget content = MessageBubble(
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
      onQuickReact: isRedacted ? null : (emoji) => _toggleReaction(event, emoji),
      onPin: canPin ? () => _togglePin(event) : null,
      reactionBubble: reactionBubble,
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
          unawaited(
            Clipboard.setData(
              ClipboardData(text: stripReplyFallback(displayEvent.body)),
            ),
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

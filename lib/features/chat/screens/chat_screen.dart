import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lattice/core/models/pending_attachment.dart';
import 'package:lattice/core/models/upload_state.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/chat/services/chat_search_controller.dart';
import 'package:lattice/features/chat/services/compose_state_controller.dart';
import 'package:lattice/features/chat/services/typing_controller.dart';
import 'package:lattice/features/chat/services/voice_recording_controller.dart';
import 'package:lattice/features/chat/services/voice_recording_mixin.dart';
import 'package:lattice/features/chat/widgets/chat_app_bar.dart';
import 'package:lattice/features/chat/widgets/chat_message_item.dart';
import 'package:lattice/features/chat/widgets/compose_bar_section.dart';
import 'package:lattice/features/chat/widgets/desktop_drop_wrapper.dart';
import 'package:lattice/features/chat/widgets/file_send_handler.dart';
import 'package:lattice/features/chat/widgets/read_receipts.dart';
import 'package:lattice/features/chat/widgets/search_results_body.dart';
import 'package:lattice/features/chat/widgets/typing_indicator.dart';
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

class _ChatScreenState extends State<ChatScreen>
    with VoiceRecordingMixin<ChatScreen> {
  static const _historyLoadThreshold = 15;
  static const _scrollAnimationDuration = Duration(milliseconds: 400);
  static const _readMarkerDelay = Duration(seconds: 1);

  final _msgCtrl = TextEditingController();
  final _composeFocusNode = FocusNode();
  final _itemScrollCtrl = ItemScrollController();
  final _itemPosListener = ItemPositionsListener.create();
  Timeline? _timeline;
  bool _loadingHistory = false;
  Timer? _readMarkerTimer;
  int _initGeneration = 0;
  List<Event>? _cachedVisibleEvents;

  // ── Compose state ───────────────────────────────────────
  final _compose = ComposeStateController();

  // ── Typing ─────────────────────────────────────────────
  TypingController? _typingCtrl;

  // ── Voice recording ─────────────────────────────────────
  VoiceRecordingController? _voiceCtrl;

  @override
  VoiceRecordingController? get voiceController => _voiceCtrl;
  @override
  ValueNotifier<UploadState?> get voiceUploadNotifier => _compose.uploadNotifier;
  @override
  String get voiceRoomId => widget.roomId;

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
      _compose.reset(_msgCtrl);
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

  // ── Reply / Edit helpers ────────────────────────────────

  void _setReplyTo(Event event) {
    _compose.setReplyTo(event);
    _composeFocusNode.requestFocus();
  }

  void _setEditEvent(Event event) {
    _compose.setEditEvent(event, _timeline, _msgCtrl);
  }

  // ── Attachments ─────────────────────────────────────────

  void _addAttachment(PendingAttachment attachment) {
    _showAttachmentError(_compose.addAttachment(attachment));
  }

  Future<void> _handlePasteImage() async {
    final result = await _compose.handlePasteImage();
    if (mounted && result != null) _showAttachmentError(result);
  }

  void _showAttachmentError(AddAttachmentResult result) {
    switch (result) {
      case AddAttachmentResult.ok:
        return;
      case AddAttachmentResult.tooMany:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum ${ComposeStateController.maxAttachments} attachments allowed')),
        );
      case AddAttachmentResult.tooLarge:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File exceeds 25 MB limit')),
        );
    }
  }

  // ── Reactions ──────────────────────────────────────

  Future<void> _toggleReaction(Event event, String emoji) async {
    if (_timeline == null) return;
    final matrix = context.read<MatrixService>();
    final myId = matrix.client.userID;

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

  // ── Send ───────────────────────────────────────────────

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    final attachments = List<PendingAttachment>.from(_compose.pendingAttachments.value);
    if (text.isEmpty && attachments.isEmpty) return;

    _msgCtrl.clear();
    _compose.pendingAttachments.value = [];

    final replyEvent = _compose.replyNotifier.value;
    _compose.replyNotifier.value = null;

    final editEvent = _compose.editNotifier.value;
    _compose.editNotifier.value = null;

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
        uploadNotifier: _compose.uploadNotifier,
      );
      if (!ok) {
        _compose.pendingAttachments.value = attachments.sublist(i);
        if (text.isNotEmpty) {
          _msgCtrl.text = text;
          _compose.replyNotifier.value = replyEvent;
          _compose.editNotifier.value = editEvent;
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
        _compose.replyNotifier.value = replyEvent;
        _compose.editNotifier.value = editEvent;
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
    _compose.dispose();
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
        ComposeBarSection(
          replyNotifier: _compose.replyNotifier,
          editNotifier: _compose.editNotifier,
          pendingAttachments: _compose.pendingAttachments,
          controller: _msgCtrl,
          onSend: _send,
          onCancelReply: _compose.cancelReply,
          onCancelEdit: () => _compose.cancelEdit(_msgCtrl),
          onAttach: () async {
            final attachment = await pickFileAsAttachment();
            if (attachment != null && mounted) _addAttachment(attachment);
          },
          onPasteImage: _isDesktop ? _handlePasteImage : null,
          uploadNotifier: _compose.uploadNotifier,
          room: room,
          joinedRooms: matrix.rooms,
          typingController: _typingCtrl,
          focusNode: _composeFocusNode,
          voiceController: _voiceCtrl,
          onMicTap: startVoiceRecording,
          onVoiceStop: stopAndSendVoiceMessage,
          onVoiceCancel: cancelVoiceRecording,
          onRemoveAttachment: _compose.removeAttachment,
          onClearAttachments: _compose.clearAttachments,
        ),
      ],
    );

    return DesktopDropWrapper(
      enabled: _isDesktop,
      onFileDropped: _addAttachment,
      child: column,
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
        final event = events[i];
        final prevSender = i + 1 < events.length ? events[i + 1].senderId : null;
        return ChatMessageItem(
          event: event,
          isMe: event.senderId == matrix.client.userID,
          isFirst: event.senderId != prevSender,
          isMobile: isMobile,
          timeline: _timeline,
          client: matrix.client,
          highlightedEventId: _search.highlightedEventId,
          receiptMap: receiptMap,
          onReply: _setReplyTo,
          onEdit: _setEditEvent,
          onToggleReaction: _toggleReaction,
          onPin: _togglePin,
          onTapReply: _navigateToEvent,
        );
      },
    );
  }
}

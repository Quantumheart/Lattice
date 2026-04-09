import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:giphy_get/giphy_get.dart';
import 'package:lattice/core/models/pending_attachment.dart';
import 'package:lattice/core/models/upload_state.dart';
import 'package:lattice/core/services/app_config.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/core/utils/platform_info.dart';
import 'package:lattice/features/calling/models/call_constants.dart';
import 'package:lattice/features/chat/services/chat_message_actions.dart';
import 'package:lattice/features/chat/services/chat_search_controller.dart';
import 'package:lattice/features/chat/services/compose_state_controller.dart';
import 'package:lattice/features/chat/services/typing_controller.dart';
import 'package:lattice/features/chat/services/voice_recording_controller.dart';
import 'package:lattice/features/chat/services/voice_recording_mixin.dart';
import 'package:lattice/features/chat/widgets/call_event_tile.dart';
import 'package:lattice/features/chat/widgets/chat_app_bar.dart';
import 'package:lattice/features/chat/widgets/chat_message_item.dart';
import 'package:lattice/features/chat/widgets/compose_bar_section.dart';
import 'package:lattice/features/chat/widgets/desktop_drop_wrapper.dart';
import 'package:lattice/features/chat/widgets/file_send_handler.dart';
import 'package:lattice/features/chat/widgets/gif_send_handler.dart';
import 'package:lattice/features/chat/widgets/join_call_banner.dart';
import 'package:lattice/features/chat/widgets/read_receipts.dart';
import 'package:lattice/features/chat/widgets/search_results_body.dart';
import 'package:lattice/features/chat/widgets/typing_indicator.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.roomId, super.key,
    this.initialEventId,
    this.onBack,
    this.onShowDetails,
  });

  final String roomId;
  final String? initialEventId;

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
      isNativeDesktop;

  // ── Message actions ──────────────────────────────────────
  late ChatMessageActions _actions;

  // ── Search ─────────────────────────────────────────────
  late ChatSearchController _search;
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _actions = _createActions();
    _search = _createSearchController();
    unawaited(_initTimeline());
    _itemPosListener.itemPositions.addListener(_onScroll);
    _composeFocusNode.requestFocus();
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.roomId != widget.roomId ||
        old.initialEventId != widget.initialEventId) {
      _timeline?.cancelSubscriptions();
      _readMarkerTimer?.cancel();
      _compose.reset(_msgCtrl);
      _cachedVisibleEvents = null;
      _typingCtrl?.dispose();
      _voiceCtrl?.dispose();
      _search.removeListener(_onSearchChanged);
      _search.dispose();
      _actions = _createActions();
      _search = _createSearchController();
      unawaited(_initTimeline());
      _composeFocusNode.requestFocus();
    }
  }

  ChatMessageActions _createActions() {
    return ChatMessageActions(
      getRoomId: () => widget.roomId,
      getRoom: () => context.read<MatrixService>().client.getRoomById(widget.roomId),
      getTimeline: () => _timeline,
      compose: _compose,
      msgCtrl: _msgCtrl,
      getScaffold: () => ScaffoldMessenger.of(context),
      getMatrixService: () => context.read<MatrixService>(),
    );
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
      eventContextId: widget.initialEventId,
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
    if (widget.initialEventId != null) _jumpToEvent(widget.initialEventId!);
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
            ((e.type == EventTypes.Message || e.type == EventTypes.Encrypted) &&
                e.relationshipType != RelationshipTypes.edit &&
                !_isCallMemberEvent(e)) ||
            callEventTypes.contains(e.type),)
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
    unawaited(_navigateToEvent(event));
  }

  Future<void> _navigateToEvent(Event event) async {
    final index = _visibleEvents.indexWhere((e) => e.eventId == event.eventId);
    if (index == -1) {
      debugPrint(
        '[Lattice] Event not in loaded timeline, reloading: ${event.eventId}',
      );
      await _reloadTimelineAt(event.eventId);
      return;
    }
    _scrollToIndex(index, event.eventId);
  }

  Future<void> _reloadTimelineAt(String eventId) async {
    _timeline?.cancelSubscriptions();
    _cachedVisibleEvents = null;
    setState(() => _timeline = null);

    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room == null) return;

    final gen = ++_initGeneration;
    _timeline = await room.getTimeline(
      eventContextId: eventId,
      onUpdate: () {
        if (mounted) {
          _cachedVisibleEvents = null;
          setState(() {});
        }
        _markAsRead(room);
      },
    );
    if (gen != _initGeneration || !mounted) return;
    setState(() {});
    _jumpToEvent(eventId);
  }

  void _jumpToEvent(String eventId) {
    final index = _visibleEvents.indexWhere((e) => e.eventId == eventId);
    if (index == -1) {
      debugPrint('[Lattice] Event not found after context load: $eventId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load the target message'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _scrollToIndex(index, eventId);
  }

  void _scrollToIndex(int index, String eventId) {
    _search.setHighlight(eventId);
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

    final callService = context.watch<CallService>();
    final roomHasCall = callService.roomHasActiveCall(room.id);
    final isInCall = callService.activeCallRoomId == room.id;

    final column = Column(
      children: [
        if (roomHasCall && !isInCall)
          JoinCallBanner(room: room, callService: callService),
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
          onSend: _actions.send,
          onCancelReply: _compose.cancelReply,
          onCancelEdit: () => _compose.cancelEdit(_msgCtrl),
          onAttach: () async {
            final attachment = await pickFileAsAttachment();
            if (attachment != null && mounted) _addAttachment(attachment);
          },
          onGif: AppConfig.isInitialized && AppConfig.instance.giphyEnabled
              ? () async {
                  final gif = await GiphyGet.getGif(
                    context: context,
                    apiKey: AppConfig.instance.giphyApiKey!,
                  );
                  if (gif == null || !mounted) return;
                  final url = gif.images?.downsized?.url ??
                      gif.images?.original?.url;
                  if (url == null) return;
                  await sendGifFromUrl(
                    scaffold: ScaffoldMessenger.of(context),
                    room: room,
                    url: url,
                    title: gif.title ?? 'giphy',
                    uploadNotifier: _compose.uploadNotifier,
                  );
                }
              : null,
          onPasteImage: (_isDesktop || kIsWeb) ? _handlePasteImage : null,
          uploadNotifier: _compose.uploadNotifier,
          room: room,
          joinedRooms: context.read<SelectionService>().rooms,
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
      enabled: _isDesktop || kIsWeb,
      onFileDropped: _addAttachment,
      child: column,
    );
  }

  static bool _isCallEvent(Event event) => callEventTypes.contains(event.type);

  static bool _isCallMemberEvent(Event event) =>
      event.type == kCallMember ||
      event.type == kCallMemberMsc ||
      event.body.contains(kCallMember) ||
      event.body.contains(kCallMemberMsc);

  Duration? _callDuration(Event event) {
    if (event.type != kCallHangup) return null;
    final reason = event.content.tryGet<String>('reason');
    if (reason == 'invite_timeout') return null;

    final hangupCallId = event.content.tryGet<String>('call_id');
    final events = _timeline?.events;
    if (events == null) return null;

    Event? matchedInvite;
    for (final e in events) {
      if (e.type != kCallInvite) continue;
      if (!e.originServerTs.isBefore(event.originServerTs)) continue;
      if (hangupCallId != null &&
          hangupCallId.isNotEmpty &&
          e.content.tryGet<String>('call_id') == hangupCallId) {
        matchedInvite = e;
        break;
      }
      matchedInvite ??= e;
    }

    if (matchedInvite == null) return null;
    final d = event.originServerTs.difference(matchedInvite.originServerTs);
    if (d.isNegative || d.inHours >= 24) return null;
    return d;
  }

  Widget _buildMessageList(
      List<Event> events, MatrixService matrix, Room room,) {
    final isMobile = !(kIsWeb || isNativeDesktop);
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
        if (_isCallEvent(event)) {
          return CallEventTile(
            event: event,
            isMe: event.senderId == matrix.client.userID,
            duration: _callDuration(event),
          );
        }
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
          onToggleReaction: _actions.toggleReaction,
          onPin: _actions.togglePin,
          onTapReply: _navigateToEvent,
        );
      },
    );
  }
}

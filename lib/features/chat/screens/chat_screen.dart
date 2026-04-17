import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:giphy_get/giphy_get.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/chat/services/chat_message_actions.dart';
import 'package:kohera/features/chat/services/chat_search_controller.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:kohera/features/chat/services/typing_controller.dart';
import 'package:kohera/features/chat/services/voice_recording_controller.dart';
import 'package:kohera/features/chat/services/voice_recording_mixin.dart';
import 'package:kohera/features/chat/widgets/chat_app_bar.dart';
import 'package:kohera/features/chat/widgets/compose_bar_section.dart';
import 'package:kohera/features/chat/widgets/desktop_drop_wrapper.dart';
import 'package:kohera/features/chat/widgets/file_send_handler.dart';
import 'package:kohera/features/chat/widgets/gif_send_handler.dart';
import 'package:kohera/features/chat/widgets/join_call_banner.dart';
import 'package:kohera/features/chat/widgets/message_list_view.dart';
import 'package:kohera/features/chat/widgets/search_results_body.dart';
import 'package:kohera/features/chat/widgets/typing_indicator.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

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
  final _msgCtrl = TextEditingController();
  final _composeFocusNode = FocusNode();
  final _messageListKey = GlobalKey<MessageListViewState>();

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
    _initControllers();
    if (!isTouchDevice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composeFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.roomId != widget.roomId ||
        old.initialEventId != widget.initialEventId) {
      _compose.reset(_msgCtrl);
      _typingCtrl?.dispose();
      _voiceCtrl?.dispose();
      _initControllers();
      _search.removeListener(_onSearchChanged);
      _search.dispose();
      _actions = _createActions();
      _search = _createSearchController();
      if (!isTouchDevice) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _composeFocusNode.requestFocus();
        });
      }
    }
  }

  void _initControllers() {
    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room != null) {
      _typingCtrl = TypingController(room: room);
      _voiceCtrl = VoiceRecordingController();
    }
  }

  ChatMessageActions _createActions() {
    return ChatMessageActions(
      getRoomId: () => widget.roomId,
      getRoom: () => context.read<MatrixService>().client.getRoomById(widget.roomId),
      getTimeline: () => _messageListKey.currentState?.timeline,
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

  // ── Reply / Edit helpers ────────────────────────────────

  void _setReplyTo(Event event) {
    _compose.setReplyTo(event);
    _composeFocusNode.requestFocus();
  }

  void _dismissKeyboard() {
    if (_composeFocusNode.hasFocus) _composeFocusNode.unfocus();
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
    _messageListKey.currentState?.navigateToEvent(event);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _compose.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _composeFocusNode.dispose();
    _typingCtrl?.dispose();
    _voiceCtrl?.dispose();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
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
        onPinnedEvent: (event) =>
            _messageListKey.currentState?.navigateToEvent(event),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildChatBody(matrix, room),
          if (_search.isSearching)
            ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: SearchResultsBody(
                search: _search,
                onTapResult: _scrollToEvent,
              ),
            ),
        ],
      ),
    );
  }

  // ── Chat body (messages + compose) ────────────────────────

  Widget _buildChatBody(MatrixService matrix, Room room) {
    final callService = context.watch<CallService>();
    final roomHasCall = callService.roomHasActiveCall(room.id);
    final isInCall = callService.activeCallRoomId == room.id;

    final column = Column(
      children: [
        if (roomHasCall && !isInCall)
          JoinCallBanner(room: room, callService: callService),
        Expanded(
          child: MessageListView(
            key: _messageListKey,
            room: room,
            matrix: matrix,
            initialEventId: widget.initialEventId,
            highlightedEventId: _search.highlightedEventId,
            onReply: _setReplyTo,
            onEdit: (event, timeline) =>
                _compose.setEditEvent(event, timeline, _msgCtrl),
            onToggleReaction: _actions.toggleReaction,
            onPin: _actions.togglePin,
            onHighlight: _search.setHighlight,
            onScrollBack: isTouchDevice ? _dismissKeyboard : null,
          ),
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
}

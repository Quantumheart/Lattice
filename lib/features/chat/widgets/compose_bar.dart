import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lattice/core/models/upload_state.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/chat/services/typing_controller.dart';
import 'package:lattice/features/chat/services/voice_recording_controller.dart';
import 'package:lattice/features/chat/widgets/edit_preview_banner.dart';
import 'package:lattice/features/chat/widgets/mention_autocomplete_controller.dart';
import 'package:lattice/features/chat/widgets/mention_suggestion_overlay.dart';
import 'package:lattice/features/chat/widgets/recording_indicator.dart';
import 'package:lattice/features/chat/widgets/reply_preview_banner.dart';
import 'package:lattice/features/chat/widgets/upload_progress_banner.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class ComposeBar extends StatefulWidget {
  const ComposeBar({
    required this.controller, required this.onSend, required this.onCancelReply, required this.onCancelEdit, super.key,
    this.replyEvent,
    this.editEvent,
    this.onAttach,
    this.uploadNotifier,
    this.room,
    this.joinedRooms,
    this.typingController,
    this.focusNode,
    this.voiceController,
    this.onMicTap,
    this.onVoiceStop,
    this.onVoiceCancel,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final Event? replyEvent;
  final VoidCallback onCancelReply;
  final Event? editEvent;
  final VoidCallback onCancelEdit;
  final VoidCallback? onAttach;
  final ValueNotifier<UploadState?>? uploadNotifier;

  /// The current room (needed to fetch members for @-mentions).
  final Room? room;

  /// All joined rooms (needed for #-room mentions).
  final List<Room>? joinedRooms;

  /// Manages outgoing typing indicators for the current room.
  final TypingController? typingController;

  /// Optional external focus node for the compose text field.
  final FocusNode? focusNode;

  final VoiceRecordingController? voiceController;
  final VoidCallback? onMicTap;
  final VoidCallback? onVoiceStop;
  final VoidCallback? onVoiceCancel;

  @override
  State<ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<ComposeBar> {
  static final bool _isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
  FocusNode? _ownedFocusNode;
  FocusNode get _focusNode => widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  MentionAutocompleteController? _mentionController;

  @override
  void initState() {
    super.initState();
    _initMentionController();
    widget.controller.addListener(_onTextChangedForTyping);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(ComposeBar old) {
    super.didUpdateWidget(old);
    if (old.room?.id != widget.room?.id) {
      _mentionController?.removeListener(_onMentionChanged);
      _mentionController?.dispose();
      _initMentionController();
    }
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onTextChangedForTyping);
      widget.controller.addListener(_onTextChangedForTyping);
    }
  }

  void _initMentionController() {
    if (widget.room != null && widget.joinedRooms != null) {
      _mentionController = MentionAutocompleteController(
        textController: widget.controller,
        room: widget.room!,
        joinedRooms: widget.joinedRooms!,
      );
      _mentionController!.addListener(_onMentionChanged);
    } else {
      _mentionController = null;
    }
  }

  void _onMentionChanged() {
    if (mounted) setState(() {});
  }

  void _onTextChangedForTyping() {
    if (!context.read<PreferencesService>().typingIndicators) return;
    widget.typingController?.onTextChanged(widget.controller.text);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      widget.typingController?.stop();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChangedForTyping);
    _focusNode.removeListener(_onFocusChanged);
    _mentionController?.removeListener(_onMentionChanged);
    _mentionController?.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _handleSend() {
    if (_mentionController != null && _mentionController!.hasSuggestions) {
      _mentionController!.confirmSelection();
      return;
    }
    // Dismiss empty autocomplete so it doesn't linger after send.
    _mentionController?.dismiss();
    if (widget.controller.text.trim().isNotEmpty) {
      widget.typingController?.stop();
      widget.onSend();
      _focusNode.requestFocus();
    }
  }

  void _jumpToStart() {
    widget.controller.selection = const TextSelection.collapsed(offset: 0);
  }

  void _jumpToEnd() {
    widget.controller.selection =
        TextSelection.collapsed(offset: widget.controller.text.length);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final mc = _mentionController;
    if (mc == null || !mc.hasSuggestions) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      mc.moveUp();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      mc.moveDown();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      mc.confirmSelection();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      mc.dismiss();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showSuggestions = _mentionController != null &&
        _mentionController!.isActive &&
        _mentionController!.suggestions.isNotEmpty;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSuggestions)
            MentionSuggestionList(
              controller: _mentionController!,
              client: widget.room!.client,
            ),
          if (widget.editEvent != null)
            EditPreviewBanner(
              event: widget.editEvent!,
              onCancel: widget.onCancelEdit,
            )
          else if (widget.replyEvent != null)
            ReplyPreviewBanner(
              event: widget.replyEvent!,
              onCancel: widget.onCancelReply,
            ),
          if (widget.uploadNotifier != null)
            ValueListenableBuilder<UploadState?>(
              valueListenable: widget.uploadNotifier!,
              builder: (context, uploadState, _) {
                if (uploadState == null) return const SizedBox.shrink();
                return UploadProgressBanner(
                  state: uploadState,
                  onCancel: () => widget.uploadNotifier!.value = null,
                );
              },
            ),
          _buildComposeRow(cs),
        ],
      ),
    );
  }

  Widget _buildComposeRow(ColorScheme cs) {
    final vc = widget.voiceController;
    if (vc == null) return _buildDefaultRow(cs);

    return ListenableBuilder(
      listenable: vc,
      builder: (context, _) {
        final isRecording = vc.state == VoiceRecordingState.recording ||
            vc.state == VoiceRecordingState.requesting;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isRecording
              ? RecordingIndicator(
                  key: const ValueKey('recording'),
                  controller: vc,
                  onCancel: widget.onVoiceCancel ?? () {},
                  onStop: widget.onVoiceStop ?? () {},
                )
              : _buildDefaultRow(cs),
        );
      },
    );
  }

  Widget _buildDefaultRow(ColorScheme cs) {
    return Padding(
      key: const ValueKey('compose'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          _buildAttachButton(cs),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _handleSend,
                SingleActivator(LogicalKeyboardKey.arrowUp,
                    meta: _isMacOS, control: !_isMacOS,): _jumpToStart,
                SingleActivator(LogicalKeyboardKey.arrowDown,
                    meta: _isMacOS, control: !_isMacOS,): _jumpToEnd,
              },
              child: Focus(
                onKeyEvent: _handleKeyEvent,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: widget.editEvent != null
                        ? 'Edit message…'
                        : 'Type a message…',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10,),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor:
                        cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                  minLines: 1,
                  maxLines: 5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _buildSendOrMicButton(cs),
        ],
      ),
    );
  }

  Widget _buildSendOrMicButton(ColorScheme cs) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        if (!hasText && widget.voiceController != null) {
          return IconButton.filled(
            onPressed: widget.onMicTap,
            icon: const Icon(Icons.mic_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainerHighest,
              foregroundColor: cs.onSurfaceVariant,
            ),
          );
        }
        return IconButton.filled(
          onPressed: hasText ? _handleSend : null,
          icon: const Icon(Icons.send_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor:
                hasText ? cs.primary : cs.surfaceContainerHighest,
            foregroundColor:
                hasText ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        );
      },
    );
  }

  Widget _buildAttachButton(ColorScheme cs) {
    if (widget.uploadNotifier == null) {
      return IconButton(
        icon: Icon(Icons.add_rounded, color: cs.onSurfaceVariant),
        onPressed: widget.onAttach,
      );
    }

    return ValueListenableBuilder<UploadState?>(
      valueListenable: widget.uploadNotifier!,
      builder: (context, uploadState, _) {
        final isUploading =
            uploadState != null && uploadState.status == UploadStatus.uploading;
        return IconButton(
          icon: Icon(Icons.add_rounded, color: cs.onSurfaceVariant),
          onPressed: isUploading ? null : widget.onAttach,
        );
      },
    );
  }
}

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../../models/upload_state.dart';
import 'reply_preview_banner.dart';
import 'upload_progress_banner.dart';

class ComposeBar extends StatefulWidget {
  const ComposeBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.replyEvent,
    required this.onCancelReply,
    this.onAttach,
    this.uploadNotifier,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final Event? replyEvent;
  final VoidCallback onCancelReply;
  final VoidCallback? onAttach;
  final ValueNotifier<UploadState?>? uploadNotifier;

  @override
  State<ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<ComposeBar> {
  static final bool _isMacOS = Platform.isMacOS;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    if (widget.controller.text.trim().isNotEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 0,
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
          if (widget.replyEvent != null)
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
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                _buildAttachButton(cs),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter):
                          _handleSend,
                      SingleActivator(LogicalKeyboardKey.arrowUp,
                          meta: _isMacOS, control: !_isMacOS): _jumpToStart,
                      SingleActivator(LogicalKeyboardKey.arrowDown,
                          meta: _isMacOS, control: !_isMacOS): _jumpToEnd,
                    },
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.newline,
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
                        fillColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      ),
                      minLines: 1,
                      maxLines: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
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
                ),
              ],
            ),
          ),
        ],
      ),
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

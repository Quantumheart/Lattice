import 'package:flutter/material.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/features/chat/services/typing_controller.dart';
import 'package:kohera/features/chat/services/voice_recording_controller.dart';
import 'package:kohera/features/chat/widgets/compose_bar.dart';
import 'package:matrix/matrix.dart';

class ComposeBarSection extends StatelessWidget {
  const ComposeBarSection({
    required this.replyNotifier,
    required this.editNotifier,
    required this.pendingAttachments,
    required this.controller,
    required this.onSend,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.onRemoveAttachment,
    required this.onClearAttachments,
    this.onAttach,
    this.onGif,
    this.onPasteImage,
    this.uploadNotifier,
    this.room,
    this.joinedRooms,
    this.typingController,
    this.focusNode,
    this.voiceController,
    this.onMicTap,
    this.onVoiceStop,
    this.onVoiceCancel,
    super.key,
  });

  final ValueNotifier<Event?> replyNotifier;
  final ValueNotifier<Event?> editNotifier;
  final ValueNotifier<List<PendingAttachment>> pendingAttachments;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;
  final VoidCallback? onAttach;
  final VoidCallback? onGif;
  final Future<void> Function()? onPasteImage;
  final ValueNotifier<UploadState?>? uploadNotifier;
  final Room? room;
  final List<Room>? joinedRooms;
  final TypingController? typingController;
  final FocusNode? focusNode;
  final VoiceRecordingController? voiceController;
  final VoidCallback? onMicTap;
  final VoidCallback? onVoiceStop;
  final VoidCallback? onVoiceCancel;
  final void Function(int index) onRemoveAttachment;
  final VoidCallback onClearAttachments;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([replyNotifier, editNotifier, pendingAttachments]),
      builder: (context, _) {
        return ComposeBar(
          controller: controller,
          onSend: onSend,
          replyEvent: replyNotifier.value,
          onCancelReply: onCancelReply,
          editEvent: editNotifier.value,
          onCancelEdit: onCancelEdit,
          onAttach: onAttach,
          onGif: onGif,
          onPasteImage: onPasteImage,
          uploadNotifier: uploadNotifier,
          room: room,
          joinedRooms: joinedRooms,
          typingController: typingController,
          focusNode: focusNode,
          voiceController: voiceController,
          onMicTap: onMicTap,
          onVoiceStop: onVoiceStop,
          onVoiceCancel: onVoiceCancel,
          pendingAttachments: pendingAttachments.value,
          onRemoveAttachment: onRemoveAttachment,
          onClearAttachments: onClearAttachments,
        );
      },
    );
  }
}

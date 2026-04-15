import 'package:flutter/material.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:kohera/features/chat/widgets/file_send_handler.dart';
import 'package:matrix/matrix.dart';

class ChatMessageActions {
  ChatMessageActions({
    required this.getRoomId,
    required this.getRoom,
    required this.getTimeline,
    required this.compose,
    required this.msgCtrl,
    required this.getScaffold,
    required this.getMatrixService,
  });

  final String Function() getRoomId;
  final Room? Function() getRoom;
  final Timeline? Function() getTimeline;
  final ComposeStateController compose;
  final TextEditingController msgCtrl;
  final ScaffoldMessengerState Function() getScaffold;
  final MatrixService Function() getMatrixService;

  // ── Reactions ──────────────────────────────────────

  Future<void> toggleReaction(Event event, String emoji) async {
    final timeline = getTimeline();
    if (timeline == null) return;
    final myId = getMatrixService().client.userID;

    final existing = event
        .aggregatedEvents(timeline, RelationshipTypes.reaction)
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
      getScaffold().showSnackBar(
        SnackBar(
          content: Text(
            'Failed to react: ${MatrixService.friendlyAuthError(e)}',
          ),
        ),
      );
    }
  }

  // ── Pin ──────────────────────────────────────────────

  Future<void> togglePin(Event event) async {
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
      getScaffold().showSnackBar(
        SnackBar(
          content: Text(wasPinned
              ? 'Failed to unpin message'
              : 'Failed to pin message',),
        ),
      );
    }
  }

  // ── Send ───────────────────────────────────────────────

  Future<void> send() async {
    final text = msgCtrl.text.trim();
    final attachments = List<PendingAttachment>.from(compose.pendingAttachments.value);
    if (text.isEmpty && attachments.isEmpty) return;

    msgCtrl.clear();
    compose.pendingAttachments.value = [];

    final replyEvent = compose.replyNotifier.value;
    compose.replyNotifier.value = null;

    final editEvent = compose.editNotifier.value;
    compose.editNotifier.value = null;

    final scaffold = getScaffold();
    final room = getRoom();
    if (room == null) return;

    for (var i = 0; i < attachments.length; i++) {
      final ok = await sendFileBytes(
        scaffold: scaffold,
        room: room,
        name: attachments[i].name,
        bytes: attachments[i].bytes,
        uploadNotifier: compose.uploadNotifier,
      );
      if (!ok) {
        compose.pendingAttachments.value = attachments.sublist(i);
        if (text.isNotEmpty) {
          msgCtrl.text = text;
          compose.replyNotifier.value = replyEvent;
          compose.editNotifier.value = editEvent;
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
        msgCtrl.text = text;
        compose.replyNotifier.value = replyEvent;
        compose.editNotifier.value = editEvent;
        scaffold.showSnackBar(
          SnackBar(content: Text('Failed to send: ${MatrixService.friendlyAuthError(e)}')),
        );
      }
    }
  }
}

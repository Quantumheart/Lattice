import 'package:flutter/material.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/chat/widgets/paste_image_handler.dart';
import 'package:matrix/matrix.dart';

enum AddAttachmentResult { ok, tooMany, tooLarge }

class ComposeStateController {
  static const maxAttachments = 10;
  static const int maxAttachmentBytes = 25 * 1024 * 1024;

  // ── Reply state ─────────────────────────────────────────
  final replyNotifier = ValueNotifier<Event?>(null);

  // ── Edit state ──────────────────────────────────────────
  final editNotifier = ValueNotifier<Event?>(null);

  // ── Upload state ────────────────────────────────────────
  final uploadNotifier = ValueNotifier<UploadState?>(null);

  // ── Pending attachments ────────────────────────────────
  final pendingAttachments = ValueNotifier<List<PendingAttachment>>([]);

  // ── Reply ───────────────────────────────────────────────

  void setReplyTo(Event event) {
    replyNotifier.value = event;
  }

  void cancelReply() {
    replyNotifier.value = null;
  }

  // ── Edit ────────────────────────────────────────────────

  void setEditEvent(
    Event event,
    Timeline? timeline,
    TextEditingController msgCtrl,
  ) {
    replyNotifier.value = null;
    editNotifier.value = event;
    final displayEvent =
        timeline != null ? event.getDisplayEvent(timeline) : event;
    msgCtrl.text = stripReplyFallback(displayEvent.body);
    msgCtrl.selection =
        TextSelection.collapsed(offset: msgCtrl.text.length);
  }

  void cancelEdit(TextEditingController msgCtrl) {
    editNotifier.value = null;
    msgCtrl.clear();
  }

  // ── Attachments ─────────────────────────────────────────

  AddAttachmentResult addAttachment(PendingAttachment attachment) {
    if (pendingAttachments.value.length >= maxAttachments) {
      return AddAttachmentResult.tooMany;
    }
    if (attachment.bytes.length > maxAttachmentBytes) {
      return AddAttachmentResult.tooLarge;
    }
    pendingAttachments.value = [...pendingAttachments.value, attachment];
    return AddAttachmentResult.ok;
  }

  void removeAttachment(int index) {
    final list = [...pendingAttachments.value];
    list.removeAt(index);
    pendingAttachments.value = list;
  }

  void clearAttachments() {
    pendingAttachments.value = [];
  }

  // ── Clipboard paste ─────────────────────────────────────

  Future<AddAttachmentResult?> handlePasteImage() async {
    final imageData = await readClipboardImage();
    if (imageData == null) return null;

    final name = generatePasteFilename(imageData.mimeType);
    return addAttachment(
      PendingAttachment.fromBytes(bytes: imageData.bytes, name: name),
    );
  }

  // ── Reset ───────────────────────────────────────────────

  void reset(TextEditingController msgCtrl) {
    replyNotifier.value = null;
    editNotifier.value = null;
    pendingAttachments.value = [];
    msgCtrl.clear();
  }

  // ── Dispose ─────────────────────────────────────────────

  void dispose() {
    replyNotifier.dispose();
    editNotifier.dispose();
    uploadNotifier.dispose();
    pendingAttachments.dispose();
  }
}

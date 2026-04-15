import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Event>(), MockSpec<Timeline>()])
import 'compose_state_controller_test.mocks.dart';

void main() {
  late ComposeStateController controller;
  late TextEditingController msgCtrl;

  setUp(() {
    controller = ComposeStateController();
    msgCtrl = TextEditingController();
  });

  tearDown(() {
    controller.dispose();
    msgCtrl.dispose();
  });

  group('reply', () {
    test('setReplyTo sets notifier value', () {
      final event = MockEvent();
      controller.setReplyTo(event);
      expect(controller.replyNotifier.value, event);
    });

    test('cancelReply clears notifier value', () {
      controller.setReplyTo(MockEvent());
      controller.cancelReply();
      expect(controller.replyNotifier.value, isNull);
    });
  });

  group('edit', () {
    test('setEditEvent clears reply, sets edit, and populates msgCtrl', () {
      final replyEvent = MockEvent();
      controller.setReplyTo(replyEvent);

      final editEvent = MockEvent();
      when(editEvent.getDisplayEvent(any)).thenReturn(editEvent);
      when(editEvent.body).thenReturn('hello world');

      controller.setEditEvent(editEvent, MockTimeline(), msgCtrl);

      expect(controller.replyNotifier.value, isNull);
      expect(controller.editNotifier.value, editEvent);
      expect(msgCtrl.text, 'hello world');
      expect(msgCtrl.selection.baseOffset, 'hello world'.length);
    });

    test('setEditEvent strips reply fallback from body', () {
      final event = MockEvent();
      when(event.getDisplayEvent(any)).thenReturn(event);
      when(event.body).thenReturn('> quoted\n\nactual reply');

      controller.setEditEvent(event, MockTimeline(), msgCtrl);

      expect(msgCtrl.text, 'actual reply');
    });

    test('setEditEvent uses event directly when timeline is null', () {
      final event = MockEvent();
      when(event.body).thenReturn('direct body');

      controller.setEditEvent(event, null, msgCtrl);

      expect(controller.editNotifier.value, event);
      expect(msgCtrl.text, 'direct body');
    });

    test('cancelEdit clears edit and msgCtrl', () {
      final event = MockEvent();
      when(event.getDisplayEvent(any)).thenReturn(event);
      when(event.body).thenReturn('text');
      controller.setEditEvent(event, MockTimeline(), msgCtrl);

      controller.cancelEdit(msgCtrl);

      expect(controller.editNotifier.value, isNull);
      expect(msgCtrl.text, isEmpty);
    });
  });

  group('attachments', () {
    PendingAttachment makeAttachment({int size = 100}) {
      return PendingAttachment(
        bytes: Uint8List(size),
        name: 'file.png',
        isImage: true,
      );
    }

    test('addAttachment returns ok and appends', () {
      final result = controller.addAttachment(makeAttachment());
      expect(result, AddAttachmentResult.ok);
      expect(controller.pendingAttachments.value, hasLength(1));
    });

    test('addAttachment returns tooMany at limit', () {
      for (var i = 0; i < ComposeStateController.maxAttachments; i++) {
        controller.addAttachment(makeAttachment());
      }
      final result = controller.addAttachment(makeAttachment());
      expect(result, AddAttachmentResult.tooMany);
      expect(
        controller.pendingAttachments.value,
        hasLength(ComposeStateController.maxAttachments),
      );
    });

    test('addAttachment returns tooLarge over 25MB', () {
      final result = controller.addAttachment(
        makeAttachment(size: ComposeStateController.maxAttachmentBytes + 1),
      );
      expect(result, AddAttachmentResult.tooLarge);
      expect(controller.pendingAttachments.value, isEmpty);
    });

    test('removeAttachment removes by index', () {
      final a = PendingAttachment(
        bytes: Uint8List(1),
        name: 'a.png',
        isImage: true,
      );
      final b = PendingAttachment(
        bytes: Uint8List(1),
        name: 'b.png',
        isImage: true,
      );
      controller.addAttachment(a);
      controller.addAttachment(b);

      controller.removeAttachment(0);

      expect(controller.pendingAttachments.value, hasLength(1));
      expect(controller.pendingAttachments.value.first.name, 'b.png');
    });

    test('clearAttachments empties the list', () {
      controller.addAttachment(makeAttachment());
      controller.addAttachment(makeAttachment());
      controller.clearAttachments();
      expect(controller.pendingAttachments.value, isEmpty);
    });
  });

  group('reset', () {
    test('clears all state and msgCtrl', () {
      controller.setReplyTo(MockEvent());
      final editEvent = MockEvent();
      when(editEvent.getDisplayEvent(any)).thenReturn(editEvent);
      when(editEvent.body).thenReturn('text');
      controller.setEditEvent(editEvent, MockTimeline(), msgCtrl);
      controller.addAttachment(
        PendingAttachment(
          bytes: Uint8List(1),
          name: 'f.png',
          isImage: true,
        ),
      );

      controller.reset(msgCtrl);

      expect(controller.replyNotifier.value, isNull);
      expect(controller.editNotifier.value, isNull);
      expect(controller.pendingAttachments.value, isEmpty);
      expect(msgCtrl.text, isEmpty);
    });
  });
}

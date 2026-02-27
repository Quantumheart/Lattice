import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../services/matrix_service.dart';

/// Shows a confirmation dialog and redacts [event] if the user confirms.
Future<void> confirmAndDeleteEvent(BuildContext context, Event event) async {
  final matrix = context.read<MatrixService>();
  final isMe = event.senderId == matrix.client.userID;
  final title = isMe ? 'Delete message?' : 'Remove message?';
  final body = isMe
      ? 'This message will be permanently deleted for everyone.'
      : 'This message will be permanently removed from the room.';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(isMe ? 'Delete' : 'Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  try {
    await event.room.redactEvent(event.eventId);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: ${MatrixService.friendlyAuthError(e)}')),
      );
    }
  }
}

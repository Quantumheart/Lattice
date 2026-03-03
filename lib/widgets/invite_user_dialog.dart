import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide Visibility;

/// A reusable dialog that prompts for a Matrix user ID to invite to a room.
///
/// Returns the validated MXID string on success, or `null` if cancelled.
class InviteUserDialog extends StatefulWidget {
  const InviteUserDialog._({
    required this.room,
    required this.controller,
  });

  final Room room;
  final TextEditingController controller;

  /// Shows the invite dialog and returns the entered MXID, or `null`.
  static Future<String?> show(BuildContext context, {required Room room}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => InviteUserDialog._(room: room, controller: controller),
    ).whenComplete(controller.dispose);
  }

  @override
  State<InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<InviteUserDialog> {
  static final _mxidRegex = RegExp(r'^@[^:]+:.+$');
  String? _error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Invite user'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Matrix ID',
                hintText: '@user:server.com',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.error, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Invite'),
        ),
      ],
    );
  }

  void _submit() {
    final mxid = widget.controller.text.trim();
    if (mxid.isEmpty) {
      setState(() => _error = 'Please enter a Matrix ID');
      return;
    }
    if (!_mxidRegex.hasMatch(mxid)) {
      setState(() => _error = 'Invalid Matrix ID (use @user:server)');
      return;
    }
    Navigator.pop(context, mxid);
  }
}

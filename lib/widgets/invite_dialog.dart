import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';
import 'room_avatar.dart';

/// Shared dialog for accepting or declining a room/space invitation.
///
/// Returns `true` if accepted, `false` if declined, `null` if dismissed.
class InviteDialog extends StatefulWidget {
  const InviteDialog({super.key, required this.room});

  final Room room;

  /// Show the invite dialog and return the user's decision.
  static Future<bool?> show(BuildContext context, {required Room room}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => InviteDialog(room: room),
    );
  }

  @override
  State<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<InviteDialog> {
  bool _accepting = false;
  bool _declining = false;
  String? _error;

  String? get _inviterName {
    final matrix = context.read<MatrixService>();
    return matrix.inviterDisplayName(widget.room);
  }

  Future<void> _accept() async {
    setState(() { _accepting = true; _error = null; });
    try {
      await widget.room.join();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[Lattice] Accept invite failed: $e');
      if (mounted) {
        setState(() {
          _accepting = false;
          _error = MatrixService.friendlyAuthError(e);
        });
      }
    }
  }

  Future<void> _decline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline invite'),
        content: Text(
          'Decline invite to ${widget.room.getLocalizedDisplayname()}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() { _declining = true; _error = null; });
    try {
      await widget.room.leave();
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      debugPrint('[Lattice] Decline invite failed: $e');
      if (mounted) {
        setState(() {
          _declining = false;
          _error = MatrixService.friendlyAuthError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = widget.room.getLocalizedDisplayname();
    final inviter = _inviterName;
    final inFlight = _accepting || _declining;

    return AlertDialog(
      title: Text(widget.room.isSpace ? 'Space invite' : 'Room invite'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoomAvatarWidget(room: widget.room, size: 56),
            const SizedBox(height: 12),
            Text(name, style: tt.titleMedium),
            if (inviter != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Invited by $inviter',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
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
          onPressed: inFlight ? null : _decline,
          child: _declining
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Decline', style: TextStyle(color: cs.error)),
        ),
        FilledButton(
          onPressed: inFlight ? null : _accept,
          child: _accepting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : const Text('Accept'),
        ),
      ],
    );
  }
}

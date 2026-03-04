import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/shared/widgets/room_avatar.dart';

// ── Invite tile ─────────────────────────────────────────────
class InviteTile extends StatefulWidget {
  const InviteTile({super.key, required this.room});
  final Room room;

  @override
  State<InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends State<InviteTile> {
  bool _isJoining = false;
  bool _isDeclining = false;

  bool get _inFlight => _isJoining || _isDeclining;

  Future<void> _accept() async {
    if (_inFlight) return;
    final matrix = context.read<MatrixService>();
    setState(() => _isJoining = true);
    try {
      await widget.room.join();
    } catch (e) {
      debugPrint('[Lattice] Accept invite failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(MatrixService.friendlyAuthError(e))),
        );
      }
      if (mounted) setState(() => _isJoining = false);
      return;
    }
    // Join succeeded — wait briefly for the sync so the room appears as joined.
    // A timeout here is not an error; the room will appear on the next sync.
    try {
      await matrix.client.onSync.stream.first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout is fine — the join already succeeded server-side.
    }
    if (mounted) {
      context.goNamed(Routes.room, pathParameters: {'roomId': widget.room.id});
      setState(() => _isJoining = false);
    }
  }

  Future<void> _decline() async {
    if (_inFlight) return;
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

    setState(() => _isDeclining = true);
    try {
      await widget.room.leave();
    } catch (e) {
      debugPrint('[Lattice] Decline invite failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(MatrixService.friendlyAuthError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeclining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final inviter = matrix.inviterDisplayName(widget.room);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: cs.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          mouseCursor: SystemMouseCursors.click,
          onTap: _inFlight ? null : _accept,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Avatar
                if (_isJoining)
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                else
                  RoomAvatarWidget(room: widget.room, size: 48),

                const SizedBox(width: 12),

                // Name + invite subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.room.getLocalizedDisplayname(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        inviter != null
                            ? 'Invited by $inviter'
                            : 'Pending invite',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onTertiaryContainer
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Decline button
                if (_isDeclining)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: cs.error),
                    tooltip: 'Decline invite',
                    onPressed: _inFlight ? null : _decline,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

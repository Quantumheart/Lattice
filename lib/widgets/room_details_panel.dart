import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';
import 'room_avatar.dart';
import 'room_members_section.dart';
import 'shared_media_section.dart';
import 'admin_settings_section.dart';

/// Displays room details: header, actions, members, encryption,
/// media gallery, notification settings, and admin controls.
///
/// When [isFullPage] is true, wraps itself in a Scaffold with an AppBar
/// (for mobile/tablet push route). Otherwise renders as a bare panel
/// (for the desktop side panel).
class RoomDetailsPanel extends StatefulWidget {
  const RoomDetailsPanel({
    super.key,
    required this.roomId,
    this.isFullPage = false,
  });

  final String roomId;
  final bool isFullPage;

  @override
  State<RoomDetailsPanel> createState() => _RoomDetailsPanelState();
}

class _RoomDetailsPanelState extends State<RoomDetailsPanel> {
  bool _loading = false;
  String? _error;

  // ── Actions ────────────────────────────────────────────────

  Future<void> _toggleMute(Room room) async {
    setState(() { _loading = true; _error = null; });
    try {
      final current = room.pushRuleState;
      await room.setPushRuleState(
        current == PushRuleState.notify
            ? PushRuleState.mentionsOnly
            : PushRuleState.notify,
      );
    } catch (e) {
      debugPrint('[Lattice] Toggle mute failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavourite(Room room) async {
    setState(() { _loading = true; _error = null; });
    try {
      await room.setFavourite(!room.isFavourite);
    } catch (e) {
      debugPrint('[Lattice] Set favourite failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showInviteDialog(Room room) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _InviteUserDialog(room: room, controller: controller),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    setState(() { _loading = true; _error = null; });
    try {
      await room.invite(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invited $result')),
        );
      }
    } catch (e) {
      debugPrint('[Lattice] Invite failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmLeave(Room room) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave room?'),
        content: Text('You will leave "${room.getLocalizedDisplayname()}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() { _loading = true; _error = null; });
    try {
      final matrix = context.read<MatrixService>();
      await room.leave();
      matrix.selectRoom(null);
      if (mounted && widget.isFullPage) Navigator.pop(context);
    } catch (e) {
      debugPrint('[Lattice] Leave room failed: $e');
      if (mounted) setState(() { _loading = false; _error = MatrixService.friendlyAuthError(e); });
    }
  }

  Future<void> _setPushRule(Room room, PushRuleState state) async {
    setState(() { _loading = true; _error = null; });
    try {
      await room.setPushRuleState(state);
    } catch (e) {
      debugPrint('[Lattice] Set push rule failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (room == null) {
      final body = Center(child: Text('Room not found', style: tt.bodyLarge));
      return widget.isFullPage ? Scaffold(appBar: AppBar(), body: body) : body;
    }

    final content = _buildContent(room, matrix, cs, tt);

    if (widget.isFullPage) {
      return Scaffold(
        appBar: AppBar(
          title: Text(room.getLocalizedDisplayname()),
        ),
        body: content,
      );
    }

    return Container(
      color: cs.surface,
      child: content,
    );
  }

  Widget _buildContent(Room room, MatrixService matrix, ColorScheme cs, TextTheme tt) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (_loading) const LinearProgressIndicator(),
        _buildHeader(room, cs, tt),
        const Divider(),
        _buildActionsRow(room, cs, tt),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        const Divider(),
        RoomMembersSection(room: room),
        const Divider(),
        _buildEncryptionSection(room, cs, tt),
        const Divider(),
        SharedMediaSection(room: room),
        const Divider(),
        _buildNotificationSection(room, cs, tt),
        if (room.ownPowerLevel >= 50) ...[
          const Divider(),
          AdminSettingsSection(room: room),
        ],
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────

  Widget _buildHeader(Room room, ColorScheme cs, TextTheme tt) {
    final memberCount = room.summary.mJoinedMemberCount ?? 0;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          RoomAvatarWidget(room: room, size: 72),
          const SizedBox(height: 12),
          Text(
            room.getLocalizedDisplayname(),
            style: tt.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (room.topic.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              room.topic,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            memberCount == 1 ? '1 member' : '$memberCount members',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ── Actions row ────────────────────────────────────────────

  Widget _buildActionsRow(Room room, ColorScheme cs, TextTheme tt) {
    final isMuted = room.pushRuleState != PushRuleState.notify;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: isMuted ? Icons.notifications_off_outlined : Icons.notifications_outlined,
            label: isMuted ? 'Unmute' : 'Mute',
            onTap: _loading ? null : () => _toggleMute(room),
          ),
          _ActionButton(
            icon: room.isFavourite ? Icons.star_rounded : Icons.star_border_rounded,
            label: room.isFavourite ? 'Starred' : 'Star',
            onTap: _loading ? null : () => _toggleFavourite(room),
          ),
          _ActionButton(
            icon: Icons.person_add_outlined,
            label: 'Invite',
            onTap: _loading ? null : () => _showInviteDialog(room),
          ),
          _ActionButton(
            icon: Icons.exit_to_app_rounded,
            label: 'Leave',
            color: cs.error,
            onTap: _loading ? null : () => _confirmLeave(room),
          ),
        ],
      ),
    );
  }

  // ── Encryption section ─────────────────────────────────────

  Widget _buildEncryptionSection(Room room, ColorScheme cs, TextTheme tt) {
    final encrypted = room.encrypted;
    return ListTile(
      leading: Icon(
        encrypted ? Icons.lock_rounded : Icons.lock_open_rounded,
        color: encrypted ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(encrypted ? 'Encrypted' : 'Not encrypted'),
      subtitle: Text(
        encrypted
            ? 'Messages are end-to-end encrypted'
            : 'Messages are not encrypted',
        style: tt.bodySmall,
      ),
    );
  }

  // ── Notification settings ──────────────────────────────────

  Widget _buildNotificationSection(Room room, ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'NOTIFICATIONS',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        RadioListTile<PushRuleState>(
          title: const Text('All messages'),
          value: PushRuleState.notify,
          groupValue: room.pushRuleState,
          onChanged: _loading ? null : (v) => _setPushRule(room, v!),
        ),
        RadioListTile<PushRuleState>(
          title: const Text('Mentions only'),
          value: PushRuleState.mentionsOnly,
          groupValue: room.pushRuleState,
          onChanged: _loading ? null : (v) => _setPushRule(room, v!),
        ),
        RadioListTile<PushRuleState>(
          title: const Text('Muted'),
          value: PushRuleState.dontNotify,
          groupValue: room.pushRuleState,
          onChanged: _loading ? null : (v) => _setPushRule(room, v!),
        ),
      ],
    );
  }
}

// ── Action button ──────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap != null ? effectiveColor : effectiveColor.withValues(alpha: 0.4)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: onTap != null ? effectiveColor : effectiveColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Invite dialog ──────────────────────────────────────────────

class _InviteUserDialog extends StatefulWidget {
  const _InviteUserDialog({required this.room, required this.controller});

  final Room room;
  final TextEditingController controller;

  @override
  State<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<_InviteUserDialog> {
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
                child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
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

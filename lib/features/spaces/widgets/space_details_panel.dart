import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/rooms/widgets/admin_settings_section.dart';
import 'package:lattice/features/rooms/widgets/invite_user_dialog.dart';
import 'package:lattice/features/rooms/widgets/room_members_section.dart';
import 'package:lattice/features/spaces/widgets/notification_radio_group.dart';
import 'package:lattice/features/spaces/widgets/space_context_menu.dart';
import 'package:lattice/shared/widgets/avatar_edit_overlay.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:provider/provider.dart';

/// Displays space details: header, actions, members, and admin controls.
///
/// When [isFullPage] is true, wraps itself in a Scaffold with an AppBar
/// (for mobile/tablet push route). Otherwise renders as a bare panel
/// (for the desktop content pane).
class SpaceDetailsPanel extends StatefulWidget {
  const SpaceDetailsPanel({
    required this.spaceId, super.key,
    this.isFullPage = false,
  });

  final String spaceId;
  final bool isFullPage;

  @override
  State<SpaceDetailsPanel> createState() => _SpaceDetailsPanelState();
}

class _SpaceDetailsPanelState extends State<SpaceDetailsPanel> {
  final Set<String> _inFlight = {};
  String? _error;

  bool get _loading => _inFlight.isNotEmpty;
  bool _busy(String action) => _inFlight.contains(action);

  // ── Actions ────────────────────────────────────────────────

  Future<void> _run(String action, Future<void> Function() task) async {
    setState(() { _inFlight.add(action); _error = null; });
    try {
      await task();
    } catch (e) {
      debugPrint('[Lattice] $action failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _inFlight.remove(action));
    }
  }

  Future<void> _showInviteDialog(Room space) async {
    final result = await InviteUserDialog.show(context, room: space);
    if (result == null || !mounted) return;

    await _run('invite', () async {
      await space.invite(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invited $result')),
        );
      }
    });
  }

  Future<void> _confirmLeave(Room space) async {
    if (!mounted) return;
    await _run('leave', () => handleLeaveSpace(context, space));
  }

  Future<void> _setPushRule(Room space, PushRuleState state) =>
      _run('pushRule', () => space.setPushRuleState(state));

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final space = matrix.client.getRoomById(widget.spaceId);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (space == null) {
      final body = Center(child: Text('Space not found', style: tt.bodyLarge));
      return widget.isFullPage ? Scaffold(appBar: AppBar(), body: body) : body;
    }

    final content = _buildContent(space, cs, tt);

    if (widget.isFullPage) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.goNamed(Routes.home),
          ),
          title: Text(space.getLocalizedDisplayname()),
        ),
        body: content,
      );
    }

    return ColoredBox(
      color: cs.surface,
      child: content,
    );
  }

  Widget _buildContent(Room space, ColorScheme cs, TextTheme tt) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (_loading) const LinearProgressIndicator(),
        _buildHeader(space, cs, tt),
        const Divider(),
        _buildActionsRow(space, cs),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        const Divider(),
        RoomMembersSection(room: space),
        const Divider(),
        _buildNotificationSection(space, cs, tt),
        if (space.canChangeStateEvent(EventTypes.RoomName) ||
            space.canChangeStateEvent(EventTypes.RoomTopic) ||
            space.canChangePowerLevel) ...[
          const Divider(),
          AdminSettingsSection(room: space),
        ],
      ],
    );
  }

  // ── Notification settings ──────────────────────────────────

  Widget _buildNotificationSection(Room space, ColorScheme cs, TextTheme tt) {
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
        NotificationRadioGroup(
          groupValue: space.pushRuleState,
          onChanged: _busy('pushRule') ? null : (v) => _setPushRule(space, v!),
        ),
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────

  Widget _buildHeader(Room space, ColorScheme cs, TextTheme tt) {
    final memberCount = space.summary.mJoinedMemberCount ?? 0;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AvatarEditOverlay(room: space),
          const SizedBox(height: 12),
          Text(
            space.getLocalizedDisplayname(),
            style: tt.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (space.topic.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              space.topic,
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

  Widget _buildActionsRow(Room space, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (space.canInvite)
            _ActionButton(
              icon: Icons.person_add_outlined,
              label: 'Invite',
              onTap: _busy('invite') ? null : () => _showInviteDialog(space),
            ),
          _ActionButton(
            icon: Icons.exit_to_app_rounded,
            label: 'Leave',
            color: cs.error,
            onTap: _busy('leave') ? null : () => _confirmLeave(space),
          ),
        ],
      ),
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

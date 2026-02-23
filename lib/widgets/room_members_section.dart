import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';

/// Displays a scrollable list of room members with role badges.
/// Loads members asynchronously and shows the first 5 with an expand option.
class RoomMembersSection extends StatefulWidget {
  const RoomMembersSection({super.key, required this.room});

  final Room room;

  @override
  State<RoomMembersSection> createState() => _RoomMembersSectionState();
}

class _RoomMembersSectionState extends State<RoomMembersSection> {
  List<User> _members = [];
  bool _loading = true;
  bool _expanded = false;
  int? _lastMemberCount;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void didUpdateWidget(RoomMembersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentCount = widget.room.summary.mJoinedMemberCount;
    if (_lastMemberCount != null && currentCount != _lastMemberCount) {
      _loadMembers();
    }
  }

  void _loadMembers() {
    try {
      final members = widget.room.getParticipants();
      // Sort: admins first, then mods, then alphabetical.
      members.sort((a, b) {
        final pa = widget.room.getPowerLevelByUserId(a.id);
        final pb = widget.room.getPowerLevelByUserId(b.id);
        if (pa != pb) return pb.compareTo(pa);
        final na = a.displayName ?? a.id;
        final nb = b.displayName ?? b.id;
        return na.compareTo(nb);
      });
      setState(() {
        _members = members;
        _loading = false;
        _lastMemberCount = widget.room.summary.mJoinedMemberCount;
      });
    } catch (e) {
      debugPrint('[Lattice] Failed to load members: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'MEMBERS',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final member in _expanded ? _members : _members.take(5))
            _MemberTile(
              user: member,
              room: widget.room,
            ),
          if (_members.length > 5 && !_expanded)
            TextButton(
              onPressed: () => setState(() => _expanded = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Show all ${_members.length} members'),
              ),
            ),
        ],
      ],
    );
  }
}

// ── Member tile ────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.user, required this.room});

  final User user;
  final Room room;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final powerLevel = room.getPowerLevelByUserId(user.id);
    final displayName = user.displayName ?? user.id;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: _senderColor(user.id, cs),
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      title: Text(
        displayName,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium,
      ),
      subtitle: Text(
        user.id,
        style: tt.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _roleBadge(powerLevel, cs),
      onTap: () => _showMemberSheet(context),
    );
  }

  Widget? _roleBadge(int powerLevel, ColorScheme cs) {
    if (powerLevel >= 100) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Admin',
          style: TextStyle(fontSize: 11, color: cs.onErrorContainer),
        ),
      );
    }
    if (powerLevel >= 50) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Mod',
          style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
        ),
      );
    }
    return null;
  }

  void _showMemberSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final matrix = context.read<MatrixService>();
    final powerLevel = room.getPowerLevelByUserId(user.id);
    final displayName = user.displayName ?? user.id;
    final isMe = user.id == room.client.userID;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: _senderColor(user.id, cs),
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(displayName, style: tt.titleMedium),
              Text(user.id, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(
                _powerLevelLabel(powerLevel),
                style: tt.bodySmall?.copyWith(color: cs.primary),
              ),
              const SizedBox(height: 16),
              if (!isMe) ...[
                FilledButton.tonalIcon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final dmRoomId = await matrix.client.startDirectChat(user.id);
                      matrix.selectRoom(dmRoomId);
                    } catch (e) {
                      debugPrint('[Lattice] Start DM failed: $e');
                    }
                  },
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Send message'),
                ),
                const SizedBox(height: 8),
                if (room.canKick)
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Kick member?'),
                          content: Text('Remove $displayName from the room?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.error,
                                foregroundColor: cs.onError,
                              ),
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('Kick'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        try {
                          await room.kick(user.id);
                        } catch (e) {
                          debugPrint('[Lattice] Kick failed: $e');
                        }
                      }
                    },
                    icon: Icon(Icons.person_remove_outlined, color: cs.error),
                    label: Text('Kick', style: TextStyle(color: cs.error)),
                  ),
                if (room.canBan)
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Ban member?'),
                          content: Text('Ban $displayName from the room? This can be reversed later.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.error,
                                foregroundColor: cs.onError,
                              ),
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('Ban'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        try {
                          await room.ban(user.id);
                        } catch (e) {
                          debugPrint('[Lattice] Ban failed: $e');
                        }
                      }
                    },
                    icon: Icon(Icons.block_rounded, color: cs.error),
                    label: Text('Ban', style: TextStyle(color: cs.error)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _powerLevelLabel(int level) {
    if (level >= 100) return 'Admin (power level $level)';
    if (level >= 50) return 'Moderator (power level $level)';
    if (level > 0) return 'Power level $level';
    return 'Member';
  }

  Color _senderColor(String senderId, ColorScheme cs) {
    final hash = senderId.codeUnits.fold<int>(0, (h, c) => h + c);
    final palette = [
      cs.primary,
      cs.tertiary,
      cs.secondary,
      cs.error,
      const Color(0xFF6750A4),
      const Color(0xFFB4846C),
      const Color(0xFF7C9A6E),
      const Color(0xFFC17B5F),
    ];
    return palette[hash % palette.length];
  }
}

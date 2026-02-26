import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../user_avatar.dart';

// ── Receipt map builder ──────────────────────────────────────

/// Builds a map from eventId → list of [Receipt] for other users.
///
/// Iterates [room.receiptState.global.otherUsers] (and optionally
/// mainThread) once, so cost is O(N) where N = number of users with
/// receipts, rather than O(N×M) if we queried per-event.
Map<String, List<Receipt>> buildReceiptMap(Room room, String? myUserId) {
  final map = <String, List<Receipt>>{};
  final seen = <String>{};

  void addReceipts(Map<String, LatestReceiptStateData> users) {
    for (final entry in users.entries) {
      final userId = entry.key;
      if (userId == myUserId || seen.contains(userId)) continue;
      seen.add(userId);

      final data = entry.value;
      final user = room.unsafeGetUserFromMemoryOrFallback(userId);
      final receipt = Receipt(user, data.timestamp);
      (map[data.eventId] ??= []).add(receipt);
    }
  }

  addReceipts(room.receiptState.global.otherUsers);

  final mainThread = room.receiptState.mainThread;
  if (mainThread != null) {
    addReceipts(mainThread.otherUsers);
  }

  return map;
}

// ── ReadReceiptsRow ──────────────────────────────────────────

/// Shows up to 3 overlapping user avatars for read receipts on a message,
/// with a "+N" badge when more than 3 users have read it.
class ReadReceiptsRow extends StatelessWidget {
  const ReadReceiptsRow({
    super.key,
    required this.receipts,
    required this.client,
    required this.isMe,
  });

  final List<Receipt> receipts;
  final Client client;
  final bool isMe;

  static const double _avatarSize = 16;
  static const double _overlap = 4;
  static const int _maxVisible = 3;

  @override
  Widget build(BuildContext context) {
    if (receipts.isEmpty) return const SizedBox.shrink();

    final visibleCount = receipts.length.clamp(0, _maxVisible);
    final overflow = receipts.length - _maxVisible;

    return GestureDetector(
      onTap: () => showReadersSheet(context, receipts, client),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMe) const SizedBox(width: 44 + 8), // avatar + gap offset
            SizedBox(
              width: _avatarSize +
                  (_overlap > 0 ? (visibleCount - 1) * (_avatarSize - _overlap) : 0) +
                  (overflow > 0 ? 20 : 0),
              height: _avatarSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < visibleCount; i++)
                    Positioned(
                      left: i * (_avatarSize - _overlap),
                      child: _AvatarBorder(
                        child: UserAvatar(
                          client: client,
                          avatarUrl: receipts[i].user.avatarUrl,
                          userId: receipts[i].user.id,
                          size: _avatarSize,
                        ),
                      ),
                    ),
                  if (overflow > 0)
                    Positioned(
                      left: visibleCount * (_avatarSize - _overlap),
                      top: 0,
                      child: SizedBox(
                        height: _avatarSize,
                        child: Center(
                          child: Text(
                            '+$overflow',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds a thin background-colored border around each avatar to create
/// the overlapping "chip" effect.
class _AvatarBorder extends StatelessWidget {
  const _AvatarBorder({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).scaffoldBackgroundColor,
          width: 1.5,
        ),
      ),
      child: child,
    );
  }
}

// ── Readers bottom sheet ─────────────────────────────────────

/// Shows a modal bottom sheet listing all users who have read a message.
void showReadersSheet(
  BuildContext context,
  List<Receipt> receipts,
  Client client,
) {
  showModalBottomSheet(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Read by ${receipts.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: receipts.length,
                itemBuilder: (context, i) {
                  final receipt = receipts[i];
                  final name =
                      receipt.user.displayName ?? receipt.user.id;
                  final time = TimeOfDay.fromDateTime(receipt.time.toLocal());
                  final timeStr =
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

                  return ListTile(
                    leading: UserAvatar(
                      client: client,
                      avatarUrl: receipt.user.avatarUrl,
                      userId: receipt.user.id,
                      size: 36,
                    ),
                    title: Text(name),
                    trailing: Text(
                      timeStr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

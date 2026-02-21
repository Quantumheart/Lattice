import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';

import '../services/matrix_service.dart';
import '../services/mixins/selection_mixin.dart';
import 'room_avatar.dart';

class RoomList extends StatefulWidget {
  const RoomList({super.key});

  @override
  State<RoomList> createState() => _RoomListState();
}

class _RoomListState extends State<RoomList> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _showFilters = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _filterLabels = {
    RoomFilter.all: 'All',
    RoomFilter.directMessages: 'DMs',
    RoomFilter.groups: 'Groups',
    RoomFilter.unread: 'Unread',
    RoomFilter.favourites: 'Favourites',
  };

  static const _filterIcons = {
    RoomFilter.all: Icons.chat_bubble_outline_rounded,
    RoomFilter.directMessages: Icons.person_outline_rounded,
    RoomFilter.groups: Icons.group_outlined,
    RoomFilter.unread: Icons.mark_email_unread_outlined,
    RoomFilter.favourites: Icons.star_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final activeFilter = matrix.roomFilter;

    var rooms = matrix.rooms;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      rooms = rooms
          .where((r) => r.getLocalizedDisplayname().toLowerCase().contains(q))
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          matrix.selectedSpaceId != null
              ? (matrix.client.getRoomById(matrix.selectedSpaceId!)
                      ?.getLocalizedDisplayname() ??
                  'Space')
              : 'Chats',
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.filter_list_rounded,
              color: activeFilter != RoomFilter.all ? cs.primary : null,
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter chips ──
          if (_showFilters)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: RoomFilter.values.map((filter) {
                  final isActive = activeFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isActive,
                      label: Text(_filterLabels[filter]!),
                      avatar: Icon(
                        _filterIcons[filter],
                        size: 18,
                      ),
                      onSelected: (_) => matrix.setRoomFilter(filter),
                    ),
                  );
                }).toList(),
              ),
            ),

          // ── Search bar ──
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search everything…',
                prefixIcon:
                    Icon(Icons.search, color: cs.onSurfaceVariant),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
              ),
            ),
          ),

          // ── Section label ──
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                activeFilter == RoomFilter.all
                    ? 'RECENT'
                    : _filterLabels[activeFilter]!.toUpperCase(),
                style: tt.labelSmall?.copyWith(
                  color: cs.primary,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),

          // ── Room list ──
          Expanded(
            child: rooms.isEmpty
                ? Center(
                    child: Text(
                      _query.isNotEmpty
                          ? 'No rooms match "$_query"'
                          : activeFilter != RoomFilter.all
                              ? 'No ${_filterLabels[activeFilter]!.toLowerCase()} rooms'
                              : 'No rooms yet',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: rooms.length,
                    itemBuilder: (context, i) => _RoomTile(room: rooms[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'compose',
        onPressed: () {
          // TODO: create new DM / room
        },
        child: const Icon(Icons.edit_rounded),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = matrix.selectedRoomId == room.id;
    final unread = room.notificationCount;
    final lastEvent = room.lastEvent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => matrix.selectRoom(room.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Avatar
                RoomAvatarWidget(room: room, size: 48),

                const SizedBox(width: 12),

                // Name + last message
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.getLocalizedDisplayname(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: unread > 0
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _lastMessagePreview(lastEvent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Timestamp + badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTime(lastEvent?.originServerTs),
                      style: tt.bodyMedium?.copyWith(
                        fontSize: 11,
                        color: unread > 0
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _lastMessagePreview(Event? event) {
    if (event == null) return 'No messages yet';
    if (event.messageType == MessageTypes.Text) {
      return event.body;
    }
    if (event.messageType == MessageTypes.Image) return '📷 Image';
    if (event.messageType == MessageTypes.Video) return '🎬 Video';
    if (event.messageType == MessageTypes.File) return '📎 File';
    if (event.messageType == MessageTypes.Audio) return '🎵 Audio';
    return event.body;
  }

  String _formatTime(DateTime? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}';
  }
}

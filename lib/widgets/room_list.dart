import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';

import '../models/space_node.dart';
import '../routing/route_names.dart';
import '../services/matrix_service.dart';
import '../services/preferences_service.dart';
import '../services/room_list_search_controller.dart';
import '../utils/notification_filter.dart';
import '../utils/text_highlight.dart';
import '../utils/time_format.dart';
import 'new_dm_dialog.dart';
import 'new_room_dialog.dart';
import '../utils/reply_fallback.dart';
import 'chat/typing_indicator.dart' show TypingIndicator;
import 'room_avatar.dart';

// ── List item types for the flat interleaved list ──────────
sealed class _ListItem {}

class _HeaderItem extends _ListItem {
  final String name;
  final String sectionKey;
  final int depth;
  final int roomCount;

  _HeaderItem({
    required this.name,
    required this.sectionKey,
    required this.depth,
    required this.roomCount,
  });
}

class _RoomItem extends _ListItem {
  final Room room;
  final int depth;

  _RoomItem({required this.room, this.depth = 0});
}

class _InviteItem extends _ListItem {
  final Room room;
  _InviteItem({required this.room});
}

class _FilterBarItem extends _ListItem {}

class _MessageSearchHeaderItem extends _ListItem {
  final int? resultCount;
  final bool isLoading;
  final String? error;

  _MessageSearchHeaderItem({
    this.resultCount,
    required this.isLoading,
    this.error,
  });
}

class _MessageSearchResultItem extends _ListItem {
  final MessageSearchResult result;
  _MessageSearchResultItem({required this.result});
}

class _LoadMoreMessagesItem extends _ListItem {
  final bool isLoading;
  _LoadMoreMessagesItem({required this.isLoading});
}

class RoomList extends StatefulWidget {
  const RoomList({super.key});

  @override
  State<RoomList> createState() => _RoomListState();
}

class _RoomListState extends State<RoomList>
    with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  bool _searchOpen = false;
  late final AnimationController _searchAnimCtrl;
  late final Animation<double> _searchAnimation;
  late final AnimationController _fabAnimCtrl;
  late final Animation<double> _fabAnimation;
  bool _fabOpen = false;
  late final RoomListSearchController _messageSearch;

  @override
  void initState() {
    super.initState();
    _messageSearch = RoomListSearchController(
      getClient: () => context.read<MatrixService>().client,
    );
    _messageSearch.addListener(_onMessageSearchChanged);
    _searchAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _searchAnimation = CurvedAnimation(
      parent: _searchAnimCtrl,
      curve: Curves.easeOut,
    );
    _fabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimCtrl,
      curve: Curves.easeOut,
    );
  }

  void _onMessageSearchChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _messageSearch.removeListener(_onMessageSearchChanged);
    _messageSearch.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchAnimCtrl.dispose();
    _fabAnimCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      _searchAnimCtrl.forward();
      _searchFocus.requestFocus();
    } else {
      _searchAnimCtrl.reverse();
      _searchCtrl.clear();
      _query = '';
      _messageSearch.clear();
    }
  }

  void _closeSearch() {
    if (_searchOpen) {
      setState(() {
        _searchOpen = false;
        _searchCtrl.clear();
        _query = '';
      });
      _searchAnimCtrl.reverse();
      _messageSearch.clear();
    }
  }

  void _toggleFab() {
    setState(() => _fabOpen = !_fabOpen);
    if (_fabOpen) {
      _fabAnimCtrl.forward();
    } else {
      _fabAnimCtrl.reverse();
    }
  }

  void _closeFab() {
    if (_fabOpen) {
      setState(() => _fabOpen = false);
      _fabAnimCtrl.reverse();
    }
  }

  bool _roomMatchesQuery(Room r, String q) {
    // Room display name
    if (r.getLocalizedDisplayname().toLowerCase().contains(q)) return true;

    // Room alias / canonical alias
    final alias = r.canonicalAlias;
    if (alias.isNotEmpty && alias.toLowerCase().contains(q)) return true;

    // For DMs, check the partner's Matrix ID
    final dmPartner = r.directChatMatrixID;
    if (dmPartner != null && dmPartner.toLowerCase().contains(q)) return true;

    return false;
  }

  Set<String>? _spaceRoomIds(MatrixService matrix) {
    final selectedIds = matrix.selectedSpaceIds;
    if (selectedIds.isEmpty) return null;

    final ids = <String>{};
    void collect(SpaceNode node) {
      ids.addAll(node.directChildRoomIds);
      for (final sub in node.subspaces) {
        collect(sub);
      }
    }
    for (final node in matrix.spaceTree) {
      if (selectedIds.contains(node.room.id)) collect(node);
    }
    return ids;
  }

  List<Room> _applyFilters(
    List<Room> rooms,
    RoomCategory filter,
    PreferencesService prefs, {
    bool isInvite = false,
  }) {
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      rooms = rooms.where((r) => _roomMatchesQuery(r, q)).toList();
    }
    return switch (filter) {
      RoomCategory.all => rooms,
      RoomCategory.directMessages =>
        rooms.where((r) => r.isDirectChat).toList(),
      RoomCategory.groups => rooms.where((r) => !r.isDirectChat).toList(),
      // Invites are always "unread" and never favourited.
      RoomCategory.unread => isInvite
          ? rooms
          : rooms.where((r) => effectiveUnreadCount(r, prefs) > 0).toList(),
      RoomCategory.favourites => isInvite
          ? []
          : rooms.where((r) => r.isFavourite).toList(),
    };
  }

  List<_ListItem> _buildSectionItems(MatrixService matrix,
      PreferencesService prefs) {
    final collapsed = prefs.collapsedSpaceSections;
    final filter = prefs.roomFilter;
    final selectedIds = matrix.selectedSpaceIds;
    final tree = matrix.spaceTree;
    final items = <_ListItem>[];

    // Space filter bar
    if (selectedIds.isNotEmpty) {
      items.add(_FilterBarItem());
    }

    // Invited rooms at the top (filtered by search and category)
    final invitedRooms =
        _applyFilters(matrix.invitedRooms, filter, prefs, isInvite: true);
    for (final room in invitedRooms) {
      items.add(_InviteItem(room: room));
    }

    // Determine which top-level spaces to show
    final visibleNodes = selectedIds.isEmpty
        ? tree
        : tree
            .where((n) => selectedIds.contains(n.room.id))
            .toList();

    for (final node in visibleNodes) {
      _addSpaceSection(items, node, 0, matrix, collapsed, filter, prefs);
    }

    // Unsorted section (only when no space filter active)
    if (selectedIds.isEmpty) {
      final orphanRooms = _applyFilters(matrix.orphanRooms, filter, prefs);
      if (orphanRooms.isNotEmpty) {
        items.add(_HeaderItem(
          name: 'Unsorted',
          sectionKey: PreferencesService.unsortedSectionKey,
          depth: 0,
          roomCount: orphanRooms.length,
        ));
        if (!collapsed.contains(PreferencesService.unsortedSectionKey)) {
          for (final room in orphanRooms) {
            items.add(_RoomItem(room: room, depth: 0));
          }
        }
      }
    }

    return items;
  }

  void _addSpaceSection(
    List<_ListItem> items,
    SpaceNode node,
    int depth,
    MatrixService matrix,
    Set<String> collapsed,
    RoomCategory filter,
    PreferencesService prefs,
  ) {
    final rooms = _applyFilters(
        matrix.roomsForSpace(node.room.id), filter, prefs);

    // Count total rooms including all nested subspaces for the header
    var totalRooms = rooms.length;
    void countSubspaces(List<SpaceNode> subs) {
      for (final sub in subs) {
        totalRooms += _applyFilters(
            matrix.roomsForSpace(sub.room.id), filter, prefs).length;
        countSubspaces(sub.subspaces);
      }
    }
    countSubspaces(node.subspaces);

    // Skip entirely empty sections
    if (totalRooms == 0) return;

    items.add(_HeaderItem(
      name: node.room.getLocalizedDisplayname(),
      sectionKey: node.room.id,
      depth: depth,
      roomCount: totalRooms,
    ));

    if (!collapsed.contains(node.room.id)) {
      for (final room in rooms) {
        items.add(_RoomItem(room: room, depth: depth));
      }
      for (final sub in node.subspaces) {
        _addSpaceSection(
            items, sub, depth + 1, matrix, collapsed, filter, prefs);
      }
    }
  }

  String _appBarTitle(MatrixService matrix) {
    final ids = matrix.selectedSpaceIds;
    if (ids.isEmpty) return 'Chats';
    if (ids.length == 1) {
      return matrix.client
              .getRoomById(ids.first)
              ?.getLocalizedDisplayname() ??
          'Space';
    }
    return '${ids.length} spaces';
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;

    final items = _buildSectionItems(matrix, prefs);

    // Append message search items when query is long enough
    if (_query.trim().length >= RoomListSearchController.minQueryLength) {
      items.add(_MessageSearchHeaderItem(
        resultCount: _messageSearch.totalCount,
        isLoading: _messageSearch.isLoading,
        error: _messageSearch.error,
      ));
      for (final result in _messageSearch.results) {
        items.add(_MessageSearchResultItem(result: result));
      }
      if (_messageSearch.nextBatch != null && !_messageSearch.isLoading) {
        items.add(_LoadMoreMessagesItem(isLoading: false));
      }
    }

    // Determine if the list is truly empty (no rooms AND no message results)
    final hasRoomItems = items.any((i) =>
        i is _RoomItem || i is _InviteItem || i is _HeaderItem);
    final hasMessageResults = _messageSearch.results.isNotEmpty;
    final isMessageSearchActive = _messageSearch.isLoading;
    final isEmpty = !hasRoomItems && !hasMessageResults && !isMessageSearchActive;

    return PopScope(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _searchOpen
                ? SizeTransition(
                    sizeFactor: _searchAnimation,
                    axis: Axis.horizontal,
                    axisAlignment: -1,
                    child: TextField(
                      key: const ValueKey('search'),
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onChanged: (v) {
                        setState(() => _query = v);
                        _messageSearch.onQueryChanged(v,
                            scopeRoomIds: _spaceRoomIds(matrix));
                      },
                      decoration: InputDecoration(
                        hintText: 'Search\u2026',
                        border: InputBorder.none,
                        isDense: true,
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                  _messageSearch.clear();
                                },
                              )
                            : null,
                      ),
                    ),
                  )
                : Text(
                    _appBarTitle(matrix),
                    key: const ValueKey('title'),
                  ),
          ),
          leading: _searchOpen
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _closeSearch,
                )
              : null,
          actions: _searchOpen
              ? null
              : [
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search',
                    onPressed: _toggleSearch,
                  ),
                ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
              // ── Filter chips ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: RoomCategory.values.map((filter) {
                    return FilterChip(
                      label: Text(filter.label),
                      avatar: Icon(filter.icon, size: 18),
                      selected: prefs.roomFilter == filter,
                      onSelected: (_) => prefs.setRoomCategory(filter),
                      showCheckmark: false,
                      mouseCursor: SystemMouseCursors.click,
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 4),

              // ── Sectioned room list ──
              Expanded(
                child: isEmpty && items.isEmpty
                    ? Center(
                        child: Text(
                          _query.isNotEmpty
                              ? 'No results for "$_query"'
                              : prefs.roomFilter == RoomCategory.all
                                  ? 'No rooms yet'
                                  : 'No ${prefs.roomFilter.label.toLowerCase()}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return switch (item) {
                            _FilterBarItem() =>
                              _SpaceFilterBar(matrix: matrix),
                            _InviteItem() =>
                              _InviteTile(room: item.room),
                            _HeaderItem() => _SectionHeader(
                                item: item,
                                prefs: prefs,
                              ),
                            _RoomItem() => Padding(
                                padding: EdgeInsets.only(
                                    left: item.depth * 16.0),
                                child: _RoomTile(room: item.room),
                              ),
                            _MessageSearchHeaderItem() =>
                              _MessageSearchHeader(item: item),
                            _MessageSearchResultItem() =>
                              _MessageSearchResultTile(
                                result: item.result,
                                query: _query,
                              ),
                            _LoadMoreMessagesItem() =>
                              _LoadMoreButton(
                                isLoading: item.isLoading,
                                onPressed: () => _messageSearch.performSearch(
                                    loadMore: true),
                              ),
                          };
                        },
                      ),
              ),
            ],
          ),

          // ── Scrim overlay to dismiss speed dial ──
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeFab,
                child: const ColoredBox(
                  color: Colors.black26,
                ),
              ),
            ),

          // ── FAB + speed dial ──
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ── Mini-FABs (speed dial) ──
                SizeTransition(
                  sizeFactor: _fabAnimation,
                  axisAlignment: -1,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SpeedDialItem(
                          label: 'New Room',
                          icon: Icons.group_add_rounded,
                          onTap: () {
                            _closeFab();
                            NewRoomDialog.show(context, matrixService: matrix);
                          },
                        ),
                        const SizedBox(height: 8),
                        _SpeedDialItem(
                          label: 'New Direct Message',
                          icon: Icons.chat_bubble_outline_rounded,
                          onTap: () {
                            _closeFab();
                            NewDirectMessageDialog.show(context,
                                matrixService: matrix);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Main FAB ──
                FloatingActionButton(
                  heroTag: 'compose',
                  onPressed: _toggleFab,
                  child: AnimatedRotation(
                    turns: _fabOpen ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.edit_rounded),
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

// ── Speed dial mini-FAB ─────────────────────────────────────
class _SpeedDialItem extends StatelessWidget {
  const _SpeedDialItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          color: cs.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurface)),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}

// ── Space filter bar ────────────────────────────────────────
class _SpaceFilterBar extends StatelessWidget {
  const _SpaceFilterBar({required this.matrix});
  final MatrixService matrix;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final names = matrix.selectedSpaceIds.map((id) {
      return matrix.client.getRoomById(id)?.getLocalizedDisplayname() ??
          id;
    });
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing: ${names.join(' + ')}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.primary,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => matrix.clearSpaceSelection(),
            tooltip: 'Clear space filter',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.item, required this.prefs});
  final _HeaderItem item;
  final PreferencesService prefs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCollapsed =
        prefs.collapsedSpaceSections.contains(item.sectionKey);

    return Padding(
      padding: EdgeInsets.only(
        left: 10.0 + item.depth * 16.0,
        right: 10,
        top: 8,
        bottom: 2,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => prefs.toggleSectionCollapsed(item.sectionKey),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              Icon(
                isCollapsed
                    ? Icons.chevron_right
                    : Icons.expand_more,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.name.toUpperCase(),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${item.roomCount}',
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Invite tile ─────────────────────────────────────────────
class _InviteTile extends StatefulWidget {
  const _InviteTile({required this.room});
  final Room room;

  @override
  State<_InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends State<_InviteTile> {
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

// ── Message search header ────────────────────────────────────
class _MessageSearchHeader extends StatelessWidget {
  const _MessageSearchHeader({required this.item});
  final _MessageSearchHeaderItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.resultCount != null
                      ? 'MESSAGES (${item.resultCount})'
                      : 'MESSAGES',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (item.isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (item.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.error!,
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Message search result tile ───────────────────────────────
class _MessageSearchResultTile extends StatelessWidget {
  const _MessageSearchResultTile({
    required this.result,
    required this.query,
  });

  final MessageSearchResult result;
  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final spans = highlightSpans(result.body, query.trim());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          mouseCursor: SystemMouseCursors.click,
          onTap: () => context.goNamed(
            Routes.room,
            pathParameters: {'roomId': result.roomId},
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Room name
                Text(
                  result.roomName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                // Sender + timestamp
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        result.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      formatRelativeTimestamp(result.originServerTs),
                      style: tt.bodySmall?.copyWith(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Body with highlights
                RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: spans.map((s) {
                      return TextSpan(
                        text: s.text,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          backgroundColor: s.isMatch
                              ? cs.primaryContainer
                              : null,
                          fontWeight:
                              s.isMatch ? FontWeight.w600 : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Load more button ─────────────────────────────────────────
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : TextButton(
                onPressed: onPressed,
                child: const Text('Load more messages'),
              ),
      ),
    );
  }
}

// ── Room tile ───────────────────────────────────────────────
class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = matrix.selectedRoomId == room.id;
    final unread = effectiveUnreadCount(room, prefs);
    final lastEvent = room.lastEvent;
    final memberships = matrix.spaceMemberships(room.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          mouseCursor: SystemMouseCursors.click,
          onTap: () => context.goNamed(Routes.room, pathParameters: {'roomId': room.id}),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              room.getLocalizedDisplayname(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleMedium?.copyWith(
                                fontWeight: unread > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          // Multi-space membership dots
                          if (memberships.length >= 2) ...[
                            const SizedBox(width: 6),
                            for (var j = 0;
                                j < memberships.length && j < 4;
                                j++)
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _dotColor(j, cs),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      _buildSubtitle(matrix, prefs, lastEvent, cs, tt),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Timestamp + badge
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(lastEvent?.originServerTs),
                        style: tt.bodyMedium?.copyWith(
                          fontSize: 11,
                          color: unread > 0
                              ? cs.primary
                              : cs.onSurfaceVariant
                                  .withValues(alpha: 0.5),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle(
    MatrixService matrix,
    PreferencesService prefs,
    Event? lastEvent,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final typers = room.typingUsers
        .where((u) => u.id != matrix.client.userID)
        .toList();
    if (typers.isNotEmpty && prefs.typingIndicators) {
      return Text(
        _typingPreview(typers),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium?.copyWith(
          color: cs.primary,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Text(
      _lastMessagePreview(lastEvent, matrix.client.userID),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tt.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  String _typingPreview(List<User> typers) {
    return TypingIndicator.formatTypers(typers);
  }

  Color _dotColor(int index, ColorScheme cs) {
    final palette = [cs.primary, cs.tertiary, cs.secondary, cs.error];
    return palette[index % palette.length];
  }

  String _lastMessagePreview(Event? event, String? myUserId) {
    if (event == null) return 'No messages yet';
    if (event.redacted) {
      final isMe = event.senderId == myUserId;
      if (isMe) return 'You deleted this message';
      final redactor = event.redactedBecause?.senderId;
      final isSelfRedact = redactor == event.senderId;
      if (isSelfRedact || redactor == null) return 'This message was deleted';
      final redactorUser =
          event.room.unsafeGetUserFromMemoryOrFallback(redactor);
      return 'Deleted by ${redactorUser.displayName ?? redactor}';
    }
    final body = stripReplyFallback(event.body);
    if (event.messageType == MessageTypes.Text) {
      return body;
    }
    if (event.messageType == MessageTypes.Image) return '📷 Image';
    if (event.messageType == MessageTypes.Video) return '🎬 Video';
    if (event.messageType == MessageTypes.File) return '📎 File';
    if (event.messageType == MessageTypes.Audio) return '🎵 Audio';
    return body;
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

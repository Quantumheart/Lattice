import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:kohera/features/home/widgets/mobile_space_drawer.dart';
import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:kohera/features/rooms/widgets/invite_tile.dart';
import 'package:kohera/features/rooms/widgets/message_search_tiles.dart';
import 'package:kohera/features/rooms/widgets/new_dm_dialog.dart';
import 'package:kohera/features/rooms/widgets/new_room_dialog.dart';
import 'package:kohera/features/rooms/widgets/room_list_builder.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:kohera/features/rooms/widgets/room_section_header.dart';
import 'package:kohera/features/rooms/widgets/room_tile.dart';
import 'package:kohera/shared/widgets/speed_dial_item.dart';
import 'package:provider/provider.dart';

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
      unawaited(_searchAnimCtrl.forward());
      _searchFocus.requestFocus();
    } else {
      unawaited(_searchAnimCtrl.reverse());
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
      _searchFocus.unfocus();
      unawaited(_searchAnimCtrl.reverse());
      _messageSearch.clear();
    }
  }

  void _toggleFab() {
    setState(() => _fabOpen = !_fabOpen);
    if (_fabOpen) {
      unawaited(_fabAnimCtrl.forward());
    } else {
      unawaited(_fabAnimCtrl.reverse());
    }
  }

  void _closeFab() {
    if (_fabOpen) {
      setState(() => _fabOpen = false);
      unawaited(_fabAnimCtrl.reverse());
    }
  }

  String _appBarTitle(SelectionService selection, MatrixService matrix) {
    final ids = selection.selectedSpaceIds;
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
    final selection = context.watch<SelectionService>();
    final matrix = context.read<MatrixService>();
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;

    final items = buildSectionItems(selection, prefs, _query);

    // Pre-compute context menu eligibility data once for all tiles.
    final selectedSpaceCanManage = selection.selectedSpaceIds.any((id) {
      final space = matrix.client.getRoomById(id);
      return space != null && space.canChangeStateEvent('m.space.child');
    });
    final manageableSpaceIds = <String>{
      for (final s in selection.spaces)
        if (s.canChangeStateEvent('m.space.child')) s.id,
    };

    // Append message search items when query is long enough
    if (_query.trim().length >= RoomListSearchController.minQueryLength) {
      items.add(MessageSearchHeaderItem(
        resultCount: _messageSearch.totalCount,
        isLoading: _messageSearch.isLoading,
        error: _messageSearch.error,
      ),);
      for (final result in _messageSearch.results) {
        items.add(MessageSearchResultItem(result: result));
      }
      if (_messageSearch.nextBatch != null && !_messageSearch.isLoading) {
        items.add(LoadMoreMessagesItem(isLoading: false));
      }
    }

    // Determine if the list is truly empty (no rooms AND no message results)
    final hasRoomItems = items.any((i) =>
        i is RoomItem || i is InviteItem || i is HeaderItem,);
    final hasMessageResults = _messageSearch.results.isNotEmpty;
    final isMessageSearchActive = _messageSearch.isLoading;
    final isEmpty = !hasRoomItems && !hasMessageResults && !isMessageSearchActive;
    final isNarrow =
        MediaQuery.sizeOf(context).width < HomeShell.wideBreakpoint;

    return PopScope(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        drawer: isNarrow ? const MobileSpaceDrawer() : null,
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
                            scopeRoomIds: spaceRoomIds(selection),);
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
                    _appBarTitle(selection, matrix),
                    key: const ValueKey('title'),
                  ),
          ),
          leading: _searchOpen
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _closeSearch,
                )
              : (isNarrow
                  ? Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu),
                        tooltip: 'Spaces',
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    )
                  : null),
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
              // ── Sectioned room list ──
              Expanded(
                child: isEmpty && items.isEmpty
                    ? Center(
                        child: Text(
                          _query.isNotEmpty
                              ? 'No results for "$_query"'
                              : 'No rooms yet',
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
                            horizontal: 8, vertical: 4,),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return switch (item) {
                            InviteItem() =>
                              InviteTile(room: item.room),
                            HeaderItem() => RoomSectionHeader(
                                item: item,
                                prefs: prefs,
                                selection: selection,
                                matrixService: matrix,
                              ),
                            RoomItem() => Padding(
                                padding: EdgeInsets.only(
                                    left: item.depth * 16.0,),
                                child: Builder(builder: (_) {
                                  final memberships = selection.spaceMemberships(item.room.id);
                                  return RoomTile(
                                    room: item.room,
                                    isSelected: selection.selectedRoomId == item.room.id,
                                    memberships: memberships,
                                    hasContextMenu: selectedSpaceCanManage ||
                                        manageableSpaceIds.isNotEmpty,
                                    parentSpaceId: item.parentSpaceId,
                                    sectionRooms: item.sectionRooms,
                                  );
                                },),
                              ),
                            MessageSearchHeaderItem() =>
                              MessageSearchHeader(item: item),
                            MessageSearchResultItem() =>
                              MessageSearchResultTile(
                                result: item.result,
                                query: _query,
                              ),
                            LoadMoreMessagesItem() =>
                              LoadMoreButton(
                                isLoading: item.isLoading,
                                onPressed: () => _messageSearch.performSearch(
                                    loadMore: true,),
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
            bottom: MediaQuery.paddingOf(context).bottom + 16,
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
                        SpeedDialItem(
                          label: 'New Room',
                          icon: Icons.group_add_rounded,
                          onTap: () {
                            _closeFab();
                            unawaited(NewRoomDialog.show(context, matrixService: matrix));
                          },
                        ),
                        const SizedBox(height: 8),
                        SpeedDialItem(
                          label: 'New Direct Message',
                          icon: Icons.chat_bubble_outline_rounded,
                          onTap: () {
                            _closeFab();
                            unawaited(NewDirectMessageDialog.show(
                                context,
                                matrixService: matrix,
                            ),);
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

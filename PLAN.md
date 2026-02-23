# Plan: Redesigned Spaces, Subspaces & Room Sectioning

## Goal

Replace the current "spaces replace room list" model with a "spaces as filters over a sectioned room list" model. Rooms are grouped by space as collapsible sections. Subspaces become subsections. Room category filters (DMs, Groups, Unread, Favourites) apply orthogonally across all sections.

---

## Phase 1 — Data layer: space tree & multi-select

**Files:** `lib/models/space_node.dart` (new), `lib/services/mixins/selection_mixin.dart`, `lib/services/matrix_service.dart`

1. **Add `SpaceNode` model** in a new file `lib/models/space_node.dart`:
   ```dart
   class SpaceNode {
     final Room room;
     final List<SpaceNode> subspaces;
     final List<String> directChildRoomIds;
   }
   ```
   Separate file keeps the model independent from the mixin and testable on its own.

2. **Change `_selectedSpaceId` → `_selectedSpaceIds`** (`Set<String>`):
   - `selectSpace(String? id)` → **replaces** the set with `{id}` (single-select by default). Passing `null` clears the set.
   - `toggleSpaceSelection(String id)` → adds/removes a space from the set (for Ctrl+click / long-press multi-select).
   - `clearSpaceSelection()` → empties the set (= show all)
   - `Set<String> get selectedSpaceIds` → public getter
   - Migrate all 3 existing callers of `selectedSpaceId` directly (space_rail.dart:30,53; room_list.dart:55; home_shell.dart:231) — no backward-compatible shim needed since all files are touched in this plan.

3. **Build space tree with lazy caching**:
   - Add private `List<SpaceNode>? _cachedSpaceTree`, `Set<String>? _cachedAllSpaceRoomIds`, and `Map<String, Set<String>>? _cachedRoomToSpaces`.
   - Add `bool _spaceTreeDirty = true` flag.
   - `_rebuildSpaceTree()` — private method that builds the tree, the `_allSpaceRoomIds` set, and the `_roomToSpaces` map in a single pass. Called lazily from getters when `_spaceTreeDirty` is true.
   - Set `_spaceTreeDirty = true` in `selectSpace()`, `toggleSpaceSelection()`, and after sync events (override the sync handler in `MatrixService` to dirty the cache on each sync cycle).
   - `List<SpaceNode> get spaceTree` → returns `_cachedSpaceTree` (rebuilds if dirty).
   - Tree building logic:
     - Walk `client.rooms.where((r) => r.isSpace)`
     - For each space, check `spaceChildren` — if a child's `roomId` resolves to a **joined** space via `client.getRoomById(childId)?.isSpace == true`, it's a subspace; otherwise it's a direct room
     - Top-level spaces = spaces that are NOT a child of any other joined space
     - Return sorted by name
   - **Known limitation:** Unjoined subspaces (where `client.getRoomById()` returns null) are invisible. This is acceptable; resolving them would require `getSpaceHierarchy()` API calls which are out of scope.

4. **Change `rooms` getter** to return ALL non-space rooms unfiltered (remove the space-filtering `if (_selectedSpaceId != null)` block). The widget layer now handles filtering via `roomsForSpace()` and section building. This is a contract change — the getter becomes a simple "all non-space rooms sorted by recency."

5. **Add `orphanRooms`** getter:
   - Uses precomputed `_cachedAllSpaceRoomIds` set from `_rebuildSpaceTree()`
   - Filters `rooms` to those whose `id` is not in the set
   - O(rooms) with set lookup, not tree re-walking

6. **Add `roomsForSpace(String spaceId)`** helper:
   - Returns all non-space rooms that are direct children of that space (not recursive into subspaces — subspaces get their own section)

7. **Add `spaceMemberships(String roomId)`** helper:
   - Uses precomputed `_cachedRoomToSpaces` map (roomId → Set<spaceId>) from `_rebuildSpaceTree()`
   - O(1) map lookup per call, safe to call per room tile

8. **Add aggregate unread counts**:
   - `int unreadCountForSpace(String spaceId)` — sum of `notificationCount` for all rooms in that space (including subspace children recursively)

**Tests:** Add new test groups to `test/services/matrix_service_test.dart` (following the existing pattern of testing the mixin through `MatrixService`) in a `group('space tree', ...)` block:
- `spaceTree` builds correctly with nested subspaces
- Unjoined subspace children are ignored gracefully
- `orphanRooms` excludes rooms in any space
- `selectedSpaceIds` single-select and multi-select behavior
- `roomsForSpace` returns correct children
- `spaceMemberships` returns correct set via O(1) lookup
- `unreadCountForSpace` aggregates correctly
- `rooms` getter returns all non-space rooms unfiltered (contract change)

---

## Phase 2 — Space rail: badges, multi-select, context menu

**File:** `lib/widgets/space_rail.dart`

1. **Unread badge on `_RailIcon`**:
   - Add optional `int? unreadCount` to `_RailIcon`
   - Render a small badge (Material `Badge` or positioned `Container`) on the top-right of the icon when count > 0
   - Wire to `matrix.unreadCountForSpace(space.id)` in the `itemBuilder`

2. **Selection behavior** (single-tap = replace, modifier = toggle):
   - Change `isSelected` check from `== space.id` to `selectedSpaceIds.contains(space.id)`
   - **Single tap:** calls `matrix.selectSpace(space.id)` — replaces selection with that one space (or clears if already the only selected space)
   - **Ctrl/Cmd+click (desktop):** calls `matrix.toggleSpaceSelection(space.id)` — adds/removes from multi-select set
   - **Long-press (mobile):** same as Ctrl+click — calls `matrix.toggleSpaceSelection(space.id)`
   - Home button: calls `matrix.clearSpaceSelection()`
   - Visual: selected spaces get the filled/accent treatment; multiple can be active

3. **Context menu** (right-click / long-press on desktop):
   - Wrap each `_RailIcon` in a `GestureDetector` with `onSecondaryTapUp` (desktop right-click)
   - Show a `PopupMenu` with: "Mute space", "Leave space", "Space settings" (all as TODOs for now, no implementation needed beyond showing the menu items)
   - Note: on mobile, long-press is used for multi-select (step 2), so context menu is desktop-only via right-click

4. **Tooltip enhancement**:
   - Change tooltip from just name to: `"${space.name} · ${childCount} rooms"`

**Tests:** No new test file needed (widget is hard to unit test without full widget test infra). Manual verification.

---

## Phase 3 — Sectioned room list

**Files:** `lib/widgets/room_list.dart`, `lib/services/preferences_service.dart`

This is the largest change. The flat `ListView.builder` becomes a single `ListView.builder` with a flat interleaved list of `_SectionHeader` and `_RoomTile` items. No slivers needed — the room counts for most users (tens to low hundreds) don't warrant sliver complexity, and sticky pinned headers are not a requirement.

**Prerequisite:** Add collapsed-sections persistence to `PreferencesService` first (pulled forward from Phase 5), so collapse state is persisted from day one and has a single source of truth:
- `Set<String> get collapsedSpaceSections` — reads from `SharedPreferences` as a JSON-encoded list of space IDs
- `Future<void> toggleSectionCollapsed(String spaceId)` — adds/removes and persists

1. **Build section data**:
   - In `build()`, compute a flat `List<_ListItem>` (sealed class with `_HeaderItem` and `_RoomItem` variants) from `matrix.spaceTree`:
     ```
     for each top-level SpaceNode:
       add _HeaderItem(space name, spaceId, depth: 0)
       if not collapsed:
         add _RoomItem for each room in matrix.roomsForSpace(space.id), filtered by category + search
         for each subspace in node.subspaces:
           add _HeaderItem(subspace name, subspaceId, depth: 1)
           if not collapsed:
             add _RoomItem for each room in matrix.roomsForSpace(subspace.id), filtered
     final section: add _HeaderItem("Unsorted", null, depth: 0)
     if not collapsed: add _RoomItem for each room in matrix.orphanRooms, filtered
     ```
   - Skip sections with 0 rooms after filtering (don't show empty headers)

2. **When space filter is active** (selectedSpaceIds not empty):
   - Only show sections for selected spaces (and their subspaces)
   - Show a filter bar at top: `"Showing: Work + OSS  ✕"` with a clear button
   - The `✕` calls `matrix.clearSpaceSelection()`

3. **Section headers**:
   - New `_SectionHeader` widget: space name in `labelSmall` style, left-aligned, with collapse toggle chevron
   - Tapping the header collapses/expands that section via `prefs.toggleSectionCollapsed(spaceId)` (persisted immediately)

4. **Room category filters** stay as-is (the `FilterChip` row):
   - Applied per-section when building the room sublists
   - Empty sections after filtering are hidden

5. **Space membership dots on `_RoomTile`**:
   - Add a `Row` of small colored `Container` circles (6px diameter) after the room name
   - Colors cycle through the same palette as the rail (`_spaceColor`)
   - Only show when room belongs to 2+ spaces (single-space membership is already obvious from the section)
   - Wire to `matrix.spaceMemberships(room.id)` (O(1) map lookup)

6. **Subsection indentation**:
   - Subspace section headers get `EdgeInsets.only(left: 16)` extra padding
   - Room tiles under subspaces get the same extra left padding

7. **Remove the old `RECENT` / filter-label section header** — replaced by space section headers

8. **AppBar title**:
   - When no space selected: "Chats"
   - When one space selected: space name
   - When multiple selected: "N spaces" (e.g. "2 spaces")

**Tests:** New test file `test/widgets/room_list_test.dart`:
- Sections render correctly for a mock space tree
- Empty sections are hidden when category filter active
- Search narrows rooms within sections
- Multi-space filter bar appears and clears correctly
- Collapsed sections hide their rooms

---

## Phase 4 — Mobile layout adaptation

**File:** `lib/screens/home_shell.dart`

Keep the 3-tab layout (Chats, Spaces, Settings) — removing the Spaces tab would regress discoverability and doesn't scale for users with many spaces.

1. **Redesign `_SpaceListMobile`** (keep the Spaces tab):
   - Add a search field at the top for filtering spaces by name
   - Show unread badge counts per space (same as rail)
   - Show subspace nesting with indentation
   - Tapping a space calls `matrix.selectSpace(space.id)` and switches to the Chats tab (`setState(() => _mobileTab = 0)`)
   - Long-press a space calls `matrix.toggleSpaceSelection(space.id)` (multi-select) and switches to Chats tab

2. **Add space filter chips to mobile Chats tab**:
   - When `selectedSpaceIds` is not empty, show a horizontal scrollable row of `FilterChip`s at the top of the room list (below search, above category filters) showing selected space names with `✕` to deselect
   - Add a "Clear all" chip at the end

3. **Room list on mobile** uses the same sectioned layout as desktop (same `RoomList` widget, no changes needed — it already builds sections from `spaceTree`)

4. **Update `selectedSpaceId` references**:
   - `home_shell.dart:231` (`matrix.selectedSpaceId == space.id`) → use `selectedSpaceIds.contains(space.id)`
   - `home_shell.dart:151` (room-selected mobile check) — this uses `selectedRoomId`, not `selectedSpaceId`, so no change needed

**Tests:** Manual verification for responsive behavior.

---

## Phase 5 — Remaining preferences & persistence

**File:** `lib/services/preferences_service.dart`

Note: collapsed-sections persistence was pulled into Phase 3 (prerequisite). This phase covers remaining preference work.

1. **Space ordering** (stretch goal, can be TODO):
   - `List<String> get spaceOrder` — custom order of space IDs
   - Default: alphabetical (current behavior)
   - Future: drag-to-reorder in the rail saves order here

---

## Phase 6 — Keyboard shortcuts (stretch goal)

**File:** `lib/screens/home_shell.dart`

1. Wrap the `Scaffold` in a `Shortcuts` + `Actions` widget
2. `Ctrl+1` through `Ctrl+9` → select the Nth space (single-select via `selectSpace()`)
3. `Ctrl+0` → clear space selection (show all)
4. `Ctrl+Shift+1` through `Ctrl+Shift+9` → toggle the Nth space in multi-select (via `toggleSpaceSelection()`)

---

## File change summary

| File | Change type |
|------|-------------|
| `lib/models/space_node.dart` | New — SpaceNode data model |
| `lib/services/mixins/selection_mixin.dart` | Heavy edit — multi-select, tree building with lazy caching, precomputed lookup maps, rooms getter contract change |
| `lib/services/matrix_service.dart` | Light edit — dirty cache flag on sync |
| `lib/widgets/space_rail.dart` | Medium edit — badges, single-tap/Ctrl+click selection, context menu |
| `lib/widgets/room_list.dart` | Heavy rewrite — sectioned ListView with interleaved headers/tiles, filter bar, membership dots |
| `lib/screens/home_shell.dart` | Medium edit — mobile space list redesign, space filter chips, keyboard shortcuts |
| `lib/services/preferences_service.dart` | Light edit — collapsed sections persistence (in Phase 3) |
| `test/services/matrix_service_test.dart` | Extended — new `group('space tree', ...)` test block |
| `test/widgets/room_list_test.dart` | New — sectioned list widget tests |

## Implementation order

Phases 1 → 2 → 3 → 4 → 5 → 6, strictly sequential. Each phase should compile and pass tests before moving to the next. Phase 5 is lightweight (just space ordering TODO). Phase 6 is optional/stretch.

## Known limitations

- **Unjoined subspaces are invisible:** `space.spaceChildren` may reference rooms/subspaces the user hasn't joined. `client.getRoomById()` returns null for these, so they're silently dropped from the tree. Resolving this would require `getSpaceHierarchy()` API calls, which are out of scope.
- **Space tree rebuild cost:** The lazy cache rebuilds the full tree on each sync cycle. For users with very many spaces (50+), this could be noticeable. If profiling shows this is a problem, the tree can be incrementally updated by diffing `spaceChildren` changes, but this is premature optimization for now.

## Not in scope (future work)

- Join/create space dialog (existing TODO)
- Space management (settings, members, permissions)
- Drag-to-reorder spaces in the rail
- Per-space notification level settings
- Space discovery / public space directory
- Drag rooms between spaces
- `getSpaceHierarchy()` API calls (for now we rely on `spaceChildren` from the sync, which is sufficient for spaces the user has joined)
- Sticky/pinned section headers (could upgrade to slivers later if wanted)

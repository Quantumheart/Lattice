# Plan: Redesigned Spaces, Subspaces & Room Sectioning

## Goal

Replace the current "spaces replace room list" model with a "spaces as filters over a sectioned room list" model. Rooms are grouped by space as collapsible sections. Subspaces become subsections. Room category filters (DMs, Groups, Unread, Favourites) apply orthogonally across all sections.

---

## Phase 1 — Data layer: space tree & multi-select

**Files:** `lib/services/mixins/selection_mixin.dart`, `lib/services/matrix_service.dart`

1. **Add `SpaceNode` model** to `selection_mixin.dart`:
   ```dart
   class SpaceNode {
     final Room room;
     final List<SpaceNode> subspaces;
     final List<String> directChildRoomIds;
   }
   ```

2. **Change `_selectedSpaceId` → `_selectedSpaceIds`** (`Set<String>`):
   - `selectSpace(String? id)` → toggles a space in/out of the set
   - `clearSpaceSelection()` → empties the set (= show all)
   - `Set<String> get selectedSpaceIds` → public getter
   - Keep backward-compatible `String? get selectedSpaceId` returning `null` when empty, first element when single (for existing callers during migration)

3. **Build a `spaceTree`** getter:
   - Walk `client.rooms.where((r) => r.isSpace)`
   - For each space, check `spaceChildren` — if a child's `roomId` resolves to another space, it's a subspace; otherwise it's a direct room
   - Top-level spaces = spaces that are NOT a child of any other space
   - Return `List<SpaceNode>` sorted by name
   - Cache and invalidate on `notifyListeners()`

4. **Add `orphanRooms`** getter:
   - Rooms not in any space's `spaceChildren` (recursive across the tree)
   - Used by the room list for the "Unsorted" section

5. **Add `roomsForSpace(String spaceId)`** helper:
   - Returns all non-space rooms that are direct children of that space (not recursive into subspaces — subspaces get their own section)

6. **Add `spaceMemberships(String roomId)`** helper:
   - Returns `Set<String>` of space IDs that contain this room
   - Used to render space-membership dots on room tiles

7. **Add aggregate unread counts**:
   - `int unreadCountForSpace(String spaceId)` — sum of `notificationCount` for all rooms in that space (including subspace children)

**Tests:** New test file `test/services/selection_mixin_test.dart` covering:
- `spaceTree` builds correctly with nested subspaces
- `orphanRooms` excludes rooms in any space
- `selectedSpaceIds` multi-select toggle behavior
- `roomsForSpace` returns correct children
- `spaceMemberships` returns correct set
- `unreadCountForSpace` aggregates correctly

---

## Phase 2 — Space rail: badges, multi-select, context menu

**File:** `lib/widgets/space_rail.dart`

1. **Unread badge on `_RailIcon`**:
   - Add optional `int? unreadCount` to `_RailIcon`
   - Render a small badge (Material `Badge` or positioned `Container`) on the top-right of the icon when count > 0
   - Wire to `matrix.unreadCountForSpace(space.id)` in the `itemBuilder`

2. **Multi-select support**:
   - Change `isSelected` check from `== space.id` to `selectedSpaceIds.contains(space.id)`
   - On tap: call `matrix.selectSpace(space.id)` which toggles the set
   - Home button: calls `matrix.clearSpaceSelection()`
   - Visual: selected spaces get the filled/accent treatment; multiple can be active

3. **Context menu** (right-click / long-press):
   - Wrap each `_RailIcon` in a `GestureDetector` with `onSecondaryTapUp` (desktop) and `onLongPress` (mobile)
   - Show a `PopupMenu` with: "Mute space", "Leave space", "Space settings" (all as TODOs for now, no implementation needed beyond showing the menu items)

4. **Tooltip enhancement**:
   - Change tooltip from just name to: `"${space.name} · ${childCount} rooms"`

**Tests:** No new test file needed (widget is hard to unit test without full widget test infra). Manual verification.

---

## Phase 3 — Sectioned room list

**File:** `lib/widgets/room_list.dart`

This is the largest change. The flat `ListView.builder` becomes a `CustomScrollView` with `SliverList` sections.

1. **Build section data**:
   - In `build()`, compute sections from `matrix.spaceTree`:
     ```
     for each top-level SpaceNode:
       section header = space name
       rooms = matrix.roomsForSpace(space.id), filtered by category + search
       for each subspace in node.subspaces:
         subsection header = subspace name (indented)
         rooms = matrix.roomsForSpace(subspace.id), filtered
     final section: "Unsorted" = matrix.orphanRooms, filtered
     ```
   - Skip sections with 0 rooms after filtering (don't show empty headers)

2. **When space filter is active** (selectedSpaceIds not empty):
   - Only show sections for selected spaces (and their subspaces)
   - Show a filter bar at top: `"Showing: Work + OSS  ✕"` with a clear button
   - The `✕` calls `matrix.clearSpaceSelection()`

3. **Section headers**:
   - New `_SectionHeader` widget: space name in `labelSmall` style, left-aligned, with collapse toggle chevron
   - Tapping the header collapses/expands that section (local `StatefulWidget` state via a `Set<String> _collapsedSections`)

4. **Room category filters** stay as-is (the `FilterChip` row):
   - Applied per-section when building the room sublists
   - Empty sections after filtering are hidden

5. **Space membership dots on `_RoomTile`**:
   - Add a `Row` of small colored `Container` circles (6px diameter) after the room name
   - Colors cycle through the same palette as the rail (`_spaceColor`)
   - Only show when room belongs to 2+ spaces (single-space membership is already obvious from the section)
   - Wire to `matrix.spaceMemberships(room.id)`

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

---

## Phase 4 — Mobile layout adaptation

**File:** `lib/screens/home_shell.dart`

1. **Replace `_SpaceListMobile`** with an updated version:
   - Instead of a flat `ListView` of spaces, show the same sectioned room list
   - The "Spaces" bottom tab becomes a space picker that sets the filter (like the rail does on desktop), then switches back to the Chats tab
   - OR: Remove the separate Spaces tab entirely — spaces are now section headers in the Chats tab, and the Spaces tab becomes a simple filter picker popover

2. **Preferred approach — merge into Chats tab**:
   - Remove the Spaces bottom tab (go from 3 tabs to 2: Chats, Settings)
   - Room list on mobile uses the same sectioned layout as desktop
   - Add a horizontal scrollable row of space "chips" at the top of the room list (above search) for quick filtering — acts as the mobile equivalent of the rail
   - Tapping a chip toggles that space filter, same as rail on desktop

3. **Update `NavigationBar`**:
   - 2 destinations: Chats, Settings
   - Remove `_mobileTab == 1` case

**Tests:** Manual verification for responsive behavior.

---

## Phase 5 — Preferences & persistence

**File:** `lib/services/preferences_service.dart`

1. **Collapsed sections persistence**:
   - `Set<String> get collapsedSpaceSections` — reads from `SharedPreferences` as a JSON-encoded list of space IDs
   - `Future<void> toggleSectionCollapsed(String spaceId)` — adds/removes and persists

2. **Space ordering** (stretch goal, can be TODO):
   - `List<String> get spaceOrder` — custom order of space IDs
   - Default: alphabetical (current behavior)
   - Future: drag-to-reorder in the rail saves order here

---

## Phase 6 — Keyboard shortcuts (stretch goal)

**File:** `lib/screens/home_shell.dart`

1. Wrap the `Scaffold` in a `Shortcuts` + `Actions` widget
2. `Ctrl+1` through `Ctrl+9` → select the Nth space
3. `Ctrl+0` → clear space selection (show all)
4. `Ctrl+Shift+click` on rail → multi-select (already handled by Phase 2 toggle logic)

---

## File change summary

| File | Change type |
|------|-------------|
| `lib/services/mixins/selection_mixin.dart` | Heavy edit — SpaceNode, multi-select, tree building, helpers |
| `lib/widgets/space_rail.dart` | Medium edit — badges, multi-select visual, context menu |
| `lib/widgets/room_list.dart` | Heavy rewrite — sectioned CustomScrollView, section headers, filter bar, membership dots |
| `lib/screens/home_shell.dart` | Medium edit — mobile layout simplification, keyboard shortcuts |
| `lib/services/preferences_service.dart` | Light edit — collapsed sections persistence |
| `test/services/selection_mixin_test.dart` | New — data layer tests |
| `test/widgets/room_list_test.dart` | New — sectioned list widget tests |

## Implementation order

Phases 1 → 2 → 3 → 4 → 5 → 6, strictly sequential. Each phase should compile and pass tests before moving to the next. Phase 6 is optional/stretch.

## Not in scope (future work)

- Join/create space dialog (existing TODO)
- Space management (settings, members, permissions)
- Drag-to-reorder spaces in the rail
- Per-space notification level settings
- Space discovery / public space directory
- Drag rooms between spaces
- `getSpaceHierarchy()` API calls (for now we rely on `spaceChildren` from the sync, which is sufficient for spaces the user has joined)

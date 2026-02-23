# Plan: Phase 5 — Custom Space Ordering (Drag-to-Reorder)

## Goal

Replace the alphabetical space ordering with user-customizable drag-to-reorder in both the desktop space rail and mobile space list. Persist ordering across restarts. New spaces appear at the end; removed spaces are pruned automatically.

---

## Step 1 — Persistence layer in PreferencesService

**File:** `lib/services/preferences_service.dart`

Remove the commented-out TODO block (lines 139–143) and replace with a real implementation:

```dart
static const _spaceOrderKey = 'space_order';

List<String> get spaceOrder =>
    _prefs?.getStringList(_spaceOrderKey) ?? [];

Future<void> setSpaceOrder(List<String> order) async {
  await _prefs?.setStringList(_spaceOrderKey, order);
  notifyListeners();
}
```

Uses `getStringList`/`setStringList` consistent with `collapsedSpaceSections`.

---

## Step 2 — Ordering logic in SelectionMixin

**File:** `lib/services/mixins/selection_mixin.dart`

Only top-level spaces are reorderable. Subspaces stay sorted alphabetically (matches Discord/Slack behaviour).

1. Add a cross-mixin dependency: `PreferencesService get preferencesService;` — satisfied by `MatrixService`. This gives `SelectionMixin` access to the persisted space order without importing `PreferencesService` into the mixin directly.

   **Alternative (simpler):** Pass the order list as a parameter instead. Add `List<String> _customSpaceOrder = [];` and a method `void updateSpaceOrder(List<String> order)` that sets it and marks the tree dirty. The widget layer calls this when `PreferencesService` changes. **This avoids a new cross-mixin dependency.**

   **Decision: use the alternative** — keep the mixin decoupled from `PreferencesService`.

2. Add to `SelectionMixin`:
   ```dart
   List<String> _customSpaceOrder = [];

   void updateSpaceOrder(List<String> order) {
     _customSpaceOrder = order;
     _spaceTreeDirty = true;
     notifyListeners();
   }
   ```

3. Add a private helper `List<T> _sortByCustomOrder<T>(List<T> items, String Function(T) getId)`:
   - Items whose ID appears in `_customSpaceOrder` are placed first, in that order.
   - Remaining items (new spaces not yet in the order) are appended alphabetically at the end.
   - Used by both the `spaces` getter and the top-level sort in `_rebuildSpaceTree()`.

4. Change the `spaces` getter sort: replace `.sort((a, b) => a.getLocalizedDisplayname().compareTo(...))` with `_sortByCustomOrder(list, (r) => r.id)`.

5. Change `_rebuildSpaceTree()` top-level sort (the `..sort(...)` on `topLevel`): replace alphabetical with `_sortByCustomOrder(topLevel, (n) => n.room.id)`. Subspace sorts stay alphabetical.

---

## Step 3 — Wire ordering into MatrixService

**File:** `lib/services/matrix_service.dart`

No structural change needed — `SelectionMixin.updateSpaceOrder()` is already available through inheritance. The widget layer will call `matrix.updateSpaceOrder(prefs.spaceOrder)` reactively.

---

## Step 4 — Desktop space rail: ReorderableListView

**File:** `lib/widgets/space_rail.dart`

1. Replace `ListView.separated` (lines 42–63) with `ReorderableListView.builder`:
   ```dart
   ReorderableListView.builder(
     padding: const EdgeInsets.symmetric(vertical: 4),
     itemCount: spaces.length,
     onReorder: (oldIndex, newIndex) {
       // Standard ReorderableListView adjustment
       if (newIndex > oldIndex) newIndex--;
       final ids = spaces.map((s) => s.id).toList();
       final id = ids.removeAt(oldIndex);
       ids.insert(newIndex, id);
       prefs.setSpaceOrder(ids);
       matrix.updateSpaceOrder(ids);
     },
     proxyDecorator: (child, index, animation) {
       // Scale up slightly during drag for visual feedback
       return AnimatedBuilder(
         animation: animation,
         builder: (context, child) => Material(
           color: Colors.transparent,
           elevation: 4,
           child: child,
         ),
         child: child,
       );
     },
     itemBuilder: (context, i) {
       final space = spaces[i];
       return GestureDetector(
         key: ValueKey(space.id), // required by ReorderableListView
         // ... existing _RailIcon + context menu wrapping
       );
     },
   )
   ```

2. `ReorderableListView` requires each child to have a unique `Key`. Use `ValueKey(space.id)`.

3. Add `final prefs = context.watch<PreferencesService>();` to the `build()` method (it already has `matrix`).

4. Wire the ordering sync: In the `build()` method, after getting `matrix` and `prefs`, call `matrix.updateSpaceOrder(prefs.spaceOrder)`. This ensures the space list stays in sync with persisted order on every rebuild. The `updateSpaceOrder` method is a no-op if the order hasn't changed (cheap list equality check to avoid unnecessary dirty/notify).

5. Separators: `ReorderableListView` doesn't have a `separatorBuilder`. Add `SizedBox(height: 6)` padding directly inside each item (or use `Padding` on the `_RailIcon`).

---

## Step 5 — Mobile space list: ReorderableListView

**File:** `lib/screens/home_shell.dart`

Only top-level spaces are reorderable on mobile. Subspaces remain nested under their parent and are not independently reorderable.

1. In `_SpaceListMobileState.build()`, replace the `ListView` with `ReorderableListView.builder`:
   - `itemCount: filteredTree.length` (top-level nodes only)
   - Each item renders the top-level space tile plus its subspace children as a single unit
   - `onReorder` callback: same logic as Step 4 — reorder the top-level space IDs and persist

2. When search is active (`_query.isNotEmpty`), disable reordering — show a plain `ListView` instead, since reordering a filtered subset doesn't make sense.

3. Each top-level item needs `key: ValueKey(node.room.id)`.

---

## Step 6 — Pruning stale entries

**File:** `lib/services/mixins/selection_mixin.dart`

In `_sortByCustomOrder`, IDs in `_customSpaceOrder` that don't match any current space are silently skipped (they're filtered out during the sort). No explicit pruning step needed — stale entries are harmless and naturally resolve when the user next reorders.

Optionally, add a lazy prune in `_rebuildSpaceTree()`: if the custom order contains IDs not in the current space set, emit a pruned list back to `PreferencesService`. **Defer this — it's a nice-to-have, not required for correctness.**

---

## Step 7 — Optimize updateSpaceOrder

**File:** `lib/services/mixins/selection_mixin.dart`

Add a cheap equality check to avoid unnecessary rebuilds:

```dart
void updateSpaceOrder(List<String> order) {
  if (_listEquals(_customSpaceOrder, order)) return;
  _customSpaceOrder = order;
  _spaceTreeDirty = true;
  notifyListeners();
}

static bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

This prevents the `prefs.spaceOrder` read on every widget rebuild from triggering a tree rebuild + listener notification cycle.

---

## File change summary

| File | Change type |
|------|-------------|
| `lib/services/preferences_service.dart` | Replace commented TODO with real `spaceOrder` get/set |
| `lib/services/mixins/selection_mixin.dart` | Add `updateSpaceOrder()`, `_sortByCustomOrder()`, update `spaces` getter and tree sort |
| `lib/widgets/space_rail.dart` | Replace `ListView.separated` with `ReorderableListView.builder`, add `onReorder` |
| `lib/screens/home_shell.dart` | Replace `ListView` in `_SpaceListMobile` with `ReorderableListView.builder` |
| `test/services/matrix_service_test.dart` | Add tests for custom ordering, `_sortByCustomOrder`, and `updateSpaceOrder` |

## Implementation order

Steps 1 → 2 → 3 → 4 → 5 → 6 → 7, sequential. Steps 6 and 7 are optional refinements.

## Tests

Add to the existing `group('space tree', ...)` in `matrix_service_test.dart`:
- `updateSpaceOrder` changes the ordering of `spaces` getter
- `updateSpaceOrder` changes the ordering of top-level `spaceTree`
- Subspace ordering remains alphabetical regardless of custom order
- New spaces (not in custom order) appear at the end alphabetically
- Stale IDs in custom order are silently ignored
- `updateSpaceOrder` with identical list is a no-op (no notification)

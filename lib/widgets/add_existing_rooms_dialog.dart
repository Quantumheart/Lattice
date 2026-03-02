import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide Visibility;

import '../services/matrix_service.dart';
import 'room_avatar.dart';

// ── Add Existing Rooms to Space Dialog ───────────────────────────

class AddExistingRoomsDialog extends StatefulWidget {
  const AddExistingRoomsDialog._({
    required this.space,
    required this.matrixService,
  });

  final Room space;
  final MatrixService matrixService;

  static Future<void> show(
    BuildContext context, {
    required Room space,
    required MatrixService matrixService,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AddExistingRoomsDialog._(
        space: space,
        matrixService: matrixService,
      ),
    );
  }

  @override
  State<AddExistingRoomsDialog> createState() =>
      _AddExistingRoomsDialogState();
}

class _AddExistingRoomsDialogState extends State<AddExistingRoomsDialog> {
  final _searchController = TextEditingController();
  final Set<String> _selected = {};
  bool _loading = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Room> get _eligibleRooms {
    final existingChildIds =
        widget.space.spaceChildren.map((c) => c.roomId).toSet();
    return widget.matrixService.client.rooms
        .where((r) =>
            r.membership == Membership.join &&
            !r.isSpace &&
            !existingChildIds.contains(r.id))
        .toList()
      ..sort((a, b) => a
          .getLocalizedDisplayname()
          .toLowerCase()
          .compareTo(b.getLocalizedDisplayname().toLowerCase()));
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) return;

    setState(() => _loading = true);

    var failures = 0;
    for (final roomId in _selected) {
      try {
        await widget.space.setSpaceChild(roomId);
      } catch (e) {
        debugPrint('[Lattice] Failed to add room to space: $e');
        failures++;
      }
    }

    widget.matrixService.invalidateSpaceTree();

    if (!mounted) return;

    if (failures > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add $failures room(s)')),
      );
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _eligibleRooms;
    final filtered = _query.isEmpty
        ? eligible
        : eligible
            .where((r) => r
                .getLocalizedDisplayname()
                .toLowerCase()
                .contains(_query.toLowerCase()))
            .toList();

    return AlertDialog(
      title: const Text('Add existing rooms'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: eligible.isEmpty
            ? const Center(
                child: Text('All your rooms are already in this space.'))
            : Column(
                children: [
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Search rooms',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching rooms.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final room = filtered[index];
                              final checked = _selected.contains(room.id);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: _loading
                                    ? null
                                    : (v) => setState(() {
                                          if (v == true) {
                                            _selected.add(room.id);
                                          } else {
                                            _selected.remove(room.id);
                                          }
                                        }),
                                secondary:
                                    RoomAvatarWidget(room: room, size: 36),
                                title: Text(
                                  room.getLocalizedDisplayname(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (eligible.isNotEmpty)
          FilledButton(
            onPressed: _loading || _selected.isEmpty ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text('Add (${_selected.length})'),
          ),
      ],
    );
  }
}

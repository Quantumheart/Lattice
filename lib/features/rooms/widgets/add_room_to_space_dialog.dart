import 'package:flutter/material.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart' hide Visibility;

// ── Add Room to Space Dialog ─────────────────────────────────────

class AddRoomToSpaceDialog extends StatefulWidget {
  const AddRoomToSpaceDialog._({
    required this.room,
    required this.matrixService,
  });

  final Room room;
  final MatrixService matrixService;

  static Future<void> show(
    BuildContext context, {
    required Room room,
    required MatrixService matrixService,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AddRoomToSpaceDialog._(
        room: room,
        matrixService: matrixService,
      ),
    );
  }

  @override
  State<AddRoomToSpaceDialog> createState() => _AddRoomToSpaceDialogState();
}

class _AddRoomToSpaceDialogState extends State<AddRoomToSpaceDialog> {
  final Map<String, bool> _selected = {};
  final Map<String, bool> _suggested = {};
  bool _loading = false;

  List<Room> get _eligibleSpaces {
    final memberships = widget.matrixService.selection.spaceMemberships(widget.room.id);
    return widget.matrixService.selection.spaces
        .where((s) =>
            s.canChangeStateEvent('m.space.child') &&
            !memberships.contains(s.id),)
        .toList();
  }

  bool get _hasSelection => _selected.values.any((v) => v);

  Future<void> _submit() async {
    final spaces = _eligibleSpaces
        .where((s) => _selected[s.id] == true)
        .toList();
    if (spaces.isEmpty) return;

    setState(() => _loading = true);

    var failures = 0;
    for (final space in spaces) {
      try {
        await space.setSpaceChild(
          widget.room.id,
          suggested: _suggested[space.id] == true ? true : null,
        );
      } catch (e) {
        debugPrint('[Lattice] Failed to add room to space: $e');
        failures++;
      }
    }

    widget.matrixService.selection.invalidateSpaceTree();

    if (!mounted) return;

    if (failures > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add room to $failures space(s)')),
      );
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _eligibleSpaces;

    return AlertDialog(
      title: const Text('Add to space'),
      content: SizedBox(
        width: 400,
        child: eligible.isEmpty
            ? const Text('This room is already in all your spaces.')
            : SizedBox(
                height: 400,
                child: ListView.builder(
                  itemCount: eligible.length,
                  itemBuilder: (context, index) {
                    final space = eligible[index];
                    final checked = _selected[space.id] == true;
                    return CheckboxListTile(
                      value: checked,
                      onChanged: _loading
                          ? null
                          : (v) => setState(
                              () => _selected[space.id] = v ?? false,
                            ),
                      secondary: RoomAvatarWidget(room: space, size: 36),
                      title: Text(
                        space.getLocalizedDisplayname(),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Suggested'),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: 24,
                            child: Switch(
                              value: _suggested[space.id] == true,
                              onChanged: checked && !_loading
                                  ? (v) => setState(
                                      () => _suggested[space.id] = v,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (eligible.isNotEmpty)
          FilledButton(
            onPressed: _loading || !_hasSelection ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Add'),
          ),
      ],
    );
  }
}

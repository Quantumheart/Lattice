import 'package:flutter/material.dart';
import 'package:lattice/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart' hide Visibility;

// ── Forward Message Dialog ───────────────────────────────────

class ForwardMessageDialog extends StatefulWidget {
  const ForwardMessageDialog._({
    required this.client,
    required this.event,
  });

  final Client client;
  final Event event;

  static Future<void> show(
    BuildContext context, {
    required Client client,
    required Event event,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ForwardMessageDialog._(
        client: client,
        event: event,
      ),
    );
  }

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _loading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Room> get _rooms {
    final rooms = widget.client.rooms
        .where((r) => r.membership == Membership.join && !r.isSpace)
        .toList()
      ..sort((a, b) => a
          .getLocalizedDisplayname()
          .toLowerCase()
          .compareTo(b.getLocalizedDisplayname().toLowerCase()),);

    if (_query.isEmpty) return rooms;
    return rooms
        .where((r) => r
            .getLocalizedDisplayname()
            .toLowerCase()
            .contains(_query.toLowerCase()),)
        .toList();
  }

  Future<void> _forward(Room targetRoom) async {
    setState(() => _loading = true);

    try {
      final event = widget.event;
      final content = Map<String, Object?>.from(event.content);
      content.remove('m.relates_to');

      await targetRoom.sendEvent(content, type: event.type);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Forwarded to ${targetRoom.getLocalizedDisplayname()}'),
        ),
      );
    } catch (e) {
      debugPrint('[Lattice] Failed to forward message: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to forward message')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _rooms;

    return AlertDialog(
      title: const Text('Forward to'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('No matching rooms.'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final room = filtered[index];
                            return ListTile(
                              leading:
                                  RoomAvatarWidget(room: room, size: 36),
                              title: Text(
                                room.getLocalizedDisplayname(),
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _forward(room),
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
      ],
    );
  }
}

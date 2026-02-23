import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../services/matrix_service.dart';

/// Admin settings for a room: edit name, topic, avatar, encryption,
/// and power levels. Only rendered when the user has sufficient power level.
class AdminSettingsSection extends StatefulWidget {
  const AdminSettingsSection({super.key, required this.room});

  final Room room;

  @override
  State<AdminSettingsSection> createState() => _AdminSettingsSectionState();
}

class _AdminSettingsSectionState extends State<AdminSettingsSection> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.room.getLocalizedDisplayname();
    _topicController.text = widget.room.topic;
  }

  @override
  void didUpdateWidget(AdminSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controllers when room state changes via sync, but only if the
    // user hasn't edited the field (controller still matches old value).
    final newName = widget.room.getLocalizedDisplayname();
    final oldName = oldWidget.room.getLocalizedDisplayname();
    if (newName != oldName && _nameController.text == oldName) {
      _nameController.text = newName;
    }
    final newTopic = widget.room.topic;
    final oldTopic = oldWidget.room.topic;
    if (newTopic != oldTopic && _topicController.text == oldTopic) {
      _topicController.text = newTopic;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() { _loading = true; _error = null; _success = null; });
    try {
      await widget.room.setName(newName);
      if (mounted) setState(() => _success = 'Room name updated');
    } catch (e) {
      debugPrint('[Lattice] Set room name failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveTopic() async {
    final newTopic = _topicController.text.trim();

    setState(() { _loading = true; _error = null; _success = null; });
    try {
      await widget.room.setDescription(newTopic);
      if (mounted) setState(() => _success = 'Topic updated');
    } catch (e) {
      debugPrint('[Lattice] Set topic failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enableEncryption() async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable encryption?'),
        content: const Text(
          'This action is irreversible. Once encryption is enabled, '
          'it cannot be disabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() { _loading = true; _error = null; _success = null; });
    try {
      await widget.room.enableEncryption();
      if (mounted) setState(() => _success = 'Encryption enabled');
    } catch (e) {
      debugPrint('[Lattice] Enable encryption failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final room = widget.room;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'ADMIN SETTINGS',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),

        // Room name
        if (room.canChangeStateEvent(EventTypes.RoomName))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Room name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loading ? null : _saveName,
                  icon: const Icon(Icons.check_rounded),
                  tooltip: 'Save name',
                ),
              ],
            ),
          ),

        // Topic
        if (room.canChangeStateEvent(EventTypes.RoomTopic))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _topicController,
                    enabled: !_loading,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Topic',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loading ? null : _saveTopic,
                  icon: const Icon(Icons.check_rounded),
                  tooltip: 'Save topic',
                ),
              ],
            ),
          ),

        // Enable encryption
        if (!room.encrypted &&
            room.canChangeStateEvent(EventTypes.Encryption))
          ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Enable encryption'),
            subtitle: const Text('Irreversible'),
            trailing: FilledButton.tonal(
              onPressed: _loading ? null : _enableEncryption,
              child: const Text('Enable'),
            ),
          ),

        // Power levels
        if (room.canChangePowerLevel)
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Power levels'),
            subtitle: Text(
              'Admin: 100, Mod: 50, Default: ${_defaultPowerLevel(room)}',
              style: tt.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _loading ? null : () => _showPowerLevelDialog(room),
          ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        if (_success != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_success!, style: TextStyle(color: cs.primary, fontSize: 13)),
          ),
      ],
    );
  }

  int _defaultPowerLevel(Room room) {
    final plEvent = room.getState(EventTypes.RoomPowerLevels);
    if (plEvent == null) return 0;
    return plEvent.content.tryGet<int>('users_default') ?? 0;
  }

  void _showPowerLevelDialog(Room room) {
    final plEvent = room.getState(EventTypes.RoomPowerLevels);
    if (plEvent == null) return;

    final content = plEvent.content;
    final events = content.tryGetMap<String, Object?>('events') ?? {};

    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        return AlertDialog(
          title: const Text('Power levels'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Thresholds', style: tt.titleSmall?.copyWith(color: cs.primary)),
                  const SizedBox(height: 8),
                  _plRow('Send messages', content.tryGet<int>('events_default') ?? 0),
                  _plRow('Invite users', content.tryGet<int>('invite') ?? 0),
                  _plRow('Kick users', content.tryGet<int>('kick') ?? 50),
                  _plRow('Ban users', content.tryGet<int>('ban') ?? 50),
                  _plRow('Redact messages', content.tryGet<int>('redact') ?? 50),
                  const Divider(),
                  Text('State events', style: tt.titleSmall?.copyWith(color: cs.primary)),
                  const SizedBox(height: 8),
                  _plRow('Default state', content.tryGet<int>('state_default') ?? 50),
                  for (final entry in events.entries)
                    _plRow(
                      _friendlyEventType(entry.key),
                      entry.value is int ? entry.value as int : 0,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _plRow(String label, int level) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
          Text(
            '$level',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _friendlyEventType(String type) {
    switch (type) {
      case EventTypes.RoomName:
        return 'Room name';
      case EventTypes.RoomTopic:
        return 'Room topic';
      case EventTypes.RoomAvatar:
        return 'Room avatar';
      case EventTypes.Encryption:
        return 'Encryption';
      case EventTypes.HistoryVisibility:
        return 'History visibility';
      case EventTypes.RoomJoinRules:
        return 'Join rules';
      case EventTypes.GuestAccess:
        return 'Guest access';
      default:
        return type;
    }
  }
}

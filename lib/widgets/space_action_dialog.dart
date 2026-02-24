import 'package:flutter/material.dart' hide Visibility;
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';

// ── Popover menu ────────────────────────────────────────────────

enum _SpaceAction { create, join }

/// Shows a two-option popover anchored to the right of the "+" rail icon.
Future<void> showSpaceActionMenu(
  BuildContext context,
  RelativeRect position,
) async {
  final action = await showMenu<_SpaceAction>(
    context: context,
    position: position,
    items: const [
      PopupMenuItem(
        value: _SpaceAction.create,
        child: Row(
          children: [
            Icon(Icons.add_circle_outline),
            SizedBox(width: 10),
            Text('Create Space'),
          ],
        ),
      ),
      PopupMenuItem(
        value: _SpaceAction.join,
        child: Row(
          children: [
            Icon(Icons.tag),
            SizedBox(width: 10),
            Text('Join with Address'),
          ],
        ),
      ),
    ],
  );

  if (action == null || !context.mounted) return;

  final matrix = context.read<MatrixService>();
  switch (action) {
    case _SpaceAction.create:
      CreateSpaceDialog.show(context, matrixService: matrix);
    case _SpaceAction.join:
      JoinSpaceDialog.show(context, matrixService: matrix);
  }
}

// ── Create Space dialog ─────────────────────────────────────────

class CreateSpaceDialog extends StatefulWidget {
  const CreateSpaceDialog._({required this.matrixService});

  final MatrixService matrixService;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
  }) {
    return showDialog(
      context: context,
      builder: (_) => CreateSpaceDialog._(matrixService: matrixService),
    );
  }

  @override
  State<CreateSpaceDialog> createState() => _CreateSpaceDialogState();
}

class _CreateSpaceDialogState extends State<CreateSpaceDialog> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  bool _isPublic = false;
  bool _enableEncryption = true;
  bool _enableFederation = false;
  bool _loading = false;
  String? _nameError;
  String? _networkError;

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _nameError = 'Name is required';
        _networkError = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _nameError = null;
      _networkError = null;
    });

    try {
      final client = widget.matrixService.client;
      final topic = _topicController.text.trim();

      final roomId = await client.createRoom(
        name: name,
        topic: topic.isNotEmpty ? topic : null,
        creationContent: {
          'type': 'm.space',
          if (!_enableFederation) 'm.federate': false,
        },
        initialState: [
          if (_enableEncryption)
            StateEvent(
              content: {
                'algorithm':
                    Client.supportedGroupEncryptionAlgorithms.first,
              },
              type: EventTypes.Encryption,
            ),
        ],
        visibility: _isPublic ? Visibility.public : Visibility.private,
        powerLevelContentOverride: {'events_default': 100},
      );

      await client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      widget.matrixService.selectSpace(roomId);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _networkError = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Create Space'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: 'Name',
                border: const OutlineInputBorder(),
                errorText: _nameError,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _topicController,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Topic (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Public space'),
              value: _isPublic,
              onChanged: _loading
                  ? null
                  : (v) => setState(() {
                        _isPublic = v;
                        if (v) _enableEncryption = false;
                      }),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Enable encryption'),
              subtitle: Text(
                _isPublic
                    ? 'Not available for public spaces'
                    : 'Cannot be disabled later',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              value: _enableEncryption,
              onChanged: _loading || _isPublic
                  ? null
                  : (v) => setState(() => _enableEncryption = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Allow federation'),
              value: _enableFederation,
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _enableFederation = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_networkError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _networkError!,
                  style: TextStyle(color: cs.error, fontSize: 13),
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
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ── Join Space dialog ───────────────────────────────────────────

class JoinSpaceDialog extends StatefulWidget {
  const JoinSpaceDialog._({required this.matrixService});

  final MatrixService matrixService;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
  }) {
    return showDialog(
      context: context,
      builder: (_) => JoinSpaceDialog._(matrixService: matrixService),
    );
  }

  @override
  State<JoinSpaceDialog> createState() => _JoinSpaceDialogState();
}

class _JoinSpaceDialogState extends State<JoinSpaceDialog> {
  final _addressController = TextEditingController();
  bool _loading = false;
  String? _addressError;
  String? _networkError;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() {
        _addressError = 'Address is required';
        _networkError = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _addressError = null;
      _networkError = null;
    });

    try {
      final client = widget.matrixService.client;

      final roomId = await client.joinRoom(address);
      await client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      widget.matrixService.selectSpace(roomId);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _networkError = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Join Space'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _addressController,
              autofocus: true,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: 'Space address',
                hintText: '#space:example.com',
                border: const OutlineInputBorder(),
                errorText: _addressError,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_networkError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _networkError!,
                  style: TextStyle(color: cs.error, fontSize: 13),
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
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Join'),
        ),
      ],
    );
  }
}

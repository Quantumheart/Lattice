import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:lattice/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';

/// Dialog to create a new subspace within a parent space.
///
/// Creates a new space room and registers it as a child of [parentSpace]
/// via `setSpaceChild`.
class CreateSubspaceDialog extends StatefulWidget {
  const CreateSubspaceDialog._({
    required this.matrixService,
    required this.parentSpace,
  });

  final MatrixService matrixService;
  final Room parentSpace;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
    required Room parentSpace,
  }) {
    return showDialog(
      context: context,
      builder: (_) => CreateSubspaceDialog._(
        matrixService: matrixService,
        parentSpace: parentSpace,
      ),
    );
  }

  @override
  State<CreateSubspaceDialog> createState() => _CreateSubspaceDialogState();
}

class _CreateSubspaceDialogState extends State<CreateSubspaceDialog> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
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

      // Create the subspace room.
      final roomId = await client.createRoom(
        name: name,
        topic: topic.isNotEmpty ? topic : null,
        creationContent: {'type': 'm.space'},
        visibility: Visibility.private,
        powerLevelContentOverride: {'events_default': 100},
      );

      await client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));

      // Register as child of the parent space.
      await widget.parentSpace.setSpaceChild(roomId);
      widget.matrixService.selection.invalidateSpaceTree();

      debugPrint('[Lattice] Subspace created: $roomId under ${widget.parentSpace.id}');

      if (!mounted) return;
      Navigator.pop(context);
    } on TimeoutException {
      debugPrint('[Lattice] Subspace creation timed out');
      if (!mounted) return;
      setState(() => _networkError =
          'Timed out waiting for the server. The subspace may still be created.',);
    } catch (e) {
      debugPrint('[Lattice] Subspace creation failed: $e');
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
      title: const Text('Create subspace'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This subspace will be created inside '
              '"${widget.parentSpace.getLocalizedDisplayname()}".',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
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

import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

// ── Popover menu ────────────────────────────────────────────────

enum _SpaceAction { create, join, discover }

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
      PopupMenuItem(
        value: _SpaceAction.discover,
        child: Row(
          children: [
            Icon(Icons.explore_outlined),
            SizedBox(width: 10),
            Text('Explore spaces'),
          ],
        ),
      ),
    ],
  );

  if (action == null || !context.mounted) return;

  final matrix = context.read<MatrixService>();
  switch (action) {
    case _SpaceAction.create:
      await CreateSpaceDialog.show(context, matrixService: matrix);
    case _SpaceAction.join:
      await JoinSpaceDialog.show(context, matrixService: matrix);
    case _SpaceAction.discover:
      await SpaceDiscoveryDialog.show(context, matrixService: matrix);
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
      context.read<SelectionService>().selectSpace(roomId);
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
      final room = client.getRoomById(roomId);
      if (room != null && room.isSpace) {
        context.read<SelectionService>().selectSpace(roomId);
      }
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

// ── Space Discovery dialog ──────────────────────────────────────

class SpaceDiscoveryDialog extends StatefulWidget {
  const SpaceDiscoveryDialog._({required this.matrixService});

  final MatrixService matrixService;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SpaceDiscoveryDialog._(matrixService: matrixService),
    );
  }

  @override
  State<SpaceDiscoveryDialog> createState() => _SpaceDiscoveryDialogState();
}

class _SpaceDiscoveryDialogState extends State<SpaceDiscoveryDialog> {
  List<PublishedRoomsChunk>? _results;
  String? _error;
  String? _joiningRoomId;
  String? _joinError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _results = null;
      _error = null;
    });
    try {
      final resp =
          await widget.matrixService.client.queryPublicRooms(limit: 50);
      if (!mounted) return;
      setState(() => _results = resp.chunk);
    } catch (e) {
      debugPrint('[Kohera] Space discovery load failed: $e');
      if (!mounted) return;
      setState(() => _error = MatrixService.friendlyAuthError(e));
    }
  }

  List<String>? _viaFor(PublishedRoomsChunk chunk) {
    final alias = chunk.canonicalAlias;
    if (alias != null) {
      final idx = alias.indexOf(':');
      if (idx != -1 && idx < alias.length - 1) {
        return [alias.substring(idx + 1)];
      }
    }
    return null;
  }

  Future<void> _join(PublishedRoomsChunk chunk) async {
    if (_joiningRoomId != null) return;
    final client = widget.matrixService.client;
    final target = chunk.canonicalAlias ?? chunk.roomId;
    final via = _viaFor(chunk);

    setState(() {
      _joiningRoomId = chunk.roomId;
      _joinError = null;
    });

    try {
      final roomId = await client.joinRoom(target, via: via);
      await client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      final room = client.getRoomById(roomId);
      if (room != null && room.isSpace) {
        context.read<SelectionService>().selectSpace(roomId);
      }
      Navigator.pop(context);
    } catch (e) {
      debugPrint('[Kohera] Space discovery join failed: $e');
      if (!mounted) return;
      setState(() {
        _joinError = MatrixService.friendlyAuthError(e);
        _joiningRoomId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= HomeShell.wideBreakpoint;

    Widget body;
    if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: cs.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (_results == null) {
      body = const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    } else if (_results!.isEmpty) {
      body = Center(
        child: Text(
          'No public spaces found.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    } else {
      final list = ListView.builder(
        itemCount: _results!.length,
        itemBuilder: (context, i) {
          final chunk = _results![i];
          final title = chunk.name ??
              chunk.canonicalAlias ??
              chunk.roomId;
          final isJoining = _joiningRoomId == chunk.roomId;
          return ListTile(
            enabled: _joiningRoomId == null || isJoining,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${chunk.numJoinedMembers} members'),
            trailing: isJoining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: () => _join(chunk),
          );
        },
      );

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_joinError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _joinError!,
                style: TextStyle(color: cs.error),
              ),
            ),
          Expanded(child: list),
        ],
      );
    }

    final isJoiningAny = _joiningRoomId != null;

    return PopScope(
      canPop: !isJoiningAny,
      child: AlertDialog(
        title: const Text('Explore spaces'),
        insetPadding: isWide
            ? const EdgeInsets.symmetric(horizontal: 40, vertical: 24)
            : const EdgeInsets.all(12),
        content: SizedBox(
          width: isWide ? 480 : size.width,
          height: isWide ? 520 : size.height * 0.75,
          child: body,
        ),
        actions: [
          TextButton(
            onPressed: isJoiningAny ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

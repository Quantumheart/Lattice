import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:kohera/shared/widgets/mxc_image.dart';
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
  const SpaceDiscoveryDialog._({
    required this.matrixService,
    required this.dataSource,
  });

  final MatrixService matrixService;
  final SpaceDiscoveryDataSource dataSource;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
    SpaceDiscoveryDataSource? dataSource,
  }) {
    final ds = dataSource ??
        defaultSpaceDiscoveryDataSource(matrixService.client);
    return showDialog(
      context: context,
      builder: (_) => SpaceDiscoveryDialog._(
        matrixService: matrixService,
        dataSource: ds,
      ),
    );
  }

  @override
  State<SpaceDiscoveryDialog> createState() => _SpaceDiscoveryDialogState();
}

class _PreviewFrame {
  _PreviewFrame({
    required this.roomId,
    this.fallbackName,
    this.fallbackAvatar,
  });

  final String roomId;
  final String? fallbackName;
  final Uri? fallbackAvatar;

  GetSpaceHierarchyResponse? hierarchy;
  String? error;
}

const int _maxPreviewDepth = 5;

class _SpaceDiscoveryDialogState extends State<SpaceDiscoveryDialog> {
  static const int _pageSize = 50;

  List<PublishedRoomsChunk>? _results;
  String? _error;
  String? _joiningRoomId;
  String? _joinError;
  final List<_PreviewFrame> _previewStack = [];

  String? _nextBatch;
  bool _loadingMore = false;
  String? _paginationError;
  final Set<String> _seenRoomIds = {};

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  String _query = '';
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  PublicRoomQueryFilter _buildFilter() {
    return PublicRoomQueryFilter(
      roomTypes: ['m.space'],
      genericSearchTerm: _query.isEmpty ? null : _query,
    );
  }

  void _onSearchChanged(String text) {
    _debounceTimer?.cancel();
    final next = text.trim();
    _debounceTimer = Timer(_debounceDuration, () {
      if (!mounted) return;
      if (next == _query) return;
      _query = next;
      unawaited(_load());
    });
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _searchController.clear();
    if (_query.isEmpty) return;
    _query = '';
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _results = null;
      _error = null;
      _nextBatch = null;
      _paginationError = null;
      _seenRoomIds.clear();
    });
    try {
      final resp = await widget.dataSource.queryPublicRooms(
        limit: _pageSize,
        filter: _buildFilter(),
      );
      if (!mounted) return;
      final unique = resp.chunk.where((c) => _seenRoomIds.add(c.roomId)).toList();
      setState(() {
        _results = unique;
        _nextBatch = resp.nextBatch;
      });
    } catch (e) {
      debugPrint('[Kohera] Space discovery load failed: $e');
      if (!mounted) return;
      setState(() => _error = MatrixService.friendlyAuthError(e));
    }
  }

  bool get _hasSentinel => _nextBatch != null || _paginationError != null;

  Widget _buildSentinel() {
    final cs = Theme.of(context).colorScheme;
    if (_paginationError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _paginationError!,
              style: TextStyle(color: cs.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _loadMore,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextBatch == null || _results == null) return;
    setState(() {
      _loadingMore = true;
      _paginationError = null;
    });
    try {
      final resp = await widget.dataSource.queryPublicRooms(
        limit: _pageSize,
        since: _nextBatch,
        filter: _buildFilter(),
      );
      if (!mounted) return;
      final additions = resp.chunk.where((c) => _seenRoomIds.add(c.roomId)).toList();
      setState(() {
        _results!.addAll(additions);
        _nextBatch = resp.nextBatch;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('[Kohera] Space discovery pagination failed: $e');
      if (!mounted) return;
      setState(() {
        _paginationError = MatrixService.friendlyAuthError(e);
        _loadingMore = false;
      });
    }
  }

  List<String>? _viaFromAlias(String? alias) {
    if (alias == null) return null;
    final idx = alias.indexOf(':');
    if (idx == -1 || idx >= alias.length - 1) return null;
    return [alias.substring(idx + 1)];
  }

  bool _isMember(String roomId) => widget.dataSource.isMember(roomId);

  // ── Preview navigation ──────────────────────────────────────────

  void _openPreview(PublishedRoomsChunk chunk) {
    debugPrint('[Kohera] Space preview opened: ${chunk.roomId}');
    final frame = _PreviewFrame(
      roomId: chunk.roomId,
      fallbackName: chunk.name ?? chunk.canonicalAlias,
      fallbackAvatar: chunk.avatarUrl,
    );
    setState(() {
      _previewStack.add(frame);
      _joinError = null;
    });
    unawaited(_loadHierarchy(frame));
  }

  void _pushSubspace(SpaceRoomsChunk$2 child) {
    if (_previewStack.length >= _maxPreviewDepth) {
      debugPrint('[Kohera] Space preview stack at max depth, ignoring open');
      return;
    }
    debugPrint('[Kohera] Space subspace opened: ${child.roomId}');
    final frame = _PreviewFrame(
      roomId: child.roomId,
      fallbackName: child.name ?? child.canonicalAlias,
      fallbackAvatar: child.avatarUrl,
    );
    setState(() {
      _previewStack.add(frame);
      _joinError = null;
    });
    unawaited(_loadHierarchy(frame));
  }

  void _popPreview() {
    if (_previewStack.isEmpty) return;
    setState(() {
      _previewStack.removeLast();
      _joinError = null;
    });
  }

  Future<void> _loadHierarchy(_PreviewFrame frame) async {
    try {
      final resp = await widget.dataSource.getSpaceHierarchy(
        frame.roomId,
        maxDepth: 1,
        suggestedOnly: false,
      );
      if (!mounted) return;
      setState(() => frame.hierarchy = resp);
    } catch (e) {
      debugPrint('[Kohera] Space hierarchy fetch failed: $e');
      if (!mounted) return;
      setState(() => frame.error = MatrixService.friendlyAuthError(e));
    }
  }

  Future<void> _retryHierarchy(_PreviewFrame frame) async {
    setState(() {
      frame.error = null;
      frame.hierarchy = null;
    });
    await _loadHierarchy(frame);
  }

  // ── Join ────────────────────────────────────────────────────────

  Future<void> _joinChunk({
    required String roomId,
    String? alias,
    List<String>? via,
  }) async {
    if (_joiningRoomId != null) return;
    final target = alias ?? roomId;

    setState(() {
      _joiningRoomId = roomId;
      _joinError = null;
    });

    try {
      final joinedId =
          await widget.dataSource.joinRoom(target, via: via);

      if (!mounted) return;
      if (widget.dataSource.isSpace(joinedId)) {
        context.read<SelectionService>().selectSpace(joinedId);
        Navigator.pop(context);
        return;
      }
      setState(() => _joiningRoomId = null);
    } catch (e) {
      debugPrint('[Kohera] Space discovery join failed: $e');
      if (!mounted) return;
      setState(() {
        _joinError = MatrixService.friendlyAuthError(e);
        _joiningRoomId = null;
      });
    }
  }

  void _openExistingSpace(String roomId) {
    context.read<SelectionService>().selectSpace(roomId);
    Navigator.pop(context);
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= HomeShell.wideBreakpoint;
    final inPreview = _previewStack.isNotEmpty;
    final isJoiningAny = _joiningRoomId != null;

    final Widget content;
    final String title;
    final Widget? leading;

    if (inPreview) {
      final frame = _previewStack.last;
      content = _buildPreview(frame);
      title = frame.fallbackName ?? frame.roomId;
      leading = IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: isJoiningAny ? null : _popPreview,
      );
    } else {
      content = _buildList();
      title = 'Explore spaces';
      leading = null;
    }

    return PopScope(
      canPop: !isJoiningAny && !inPreview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inPreview && !isJoiningAny) _popPreview();
      },
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
        title: Row(
          children: [
            if (leading != null) leading else const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        insetPadding: isWide
            ? const EdgeInsets.symmetric(horizontal: 40, vertical: 24)
            : const EdgeInsets.all(12),
        content: SizedBox(
          width: isWide ? 520 : size.width,
          height: isWide ? 560 : size.height * 0.75,
          child: content,
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

  // ── List view ───────────────────────────────────────────────────

  Widget _buildList() {
    final cs = Theme.of(context).colorScheme;

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
          _query.isEmpty
              ? 'No public spaces found.'
              : 'No spaces match "$_query".',
          style: TextStyle(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      body = _buildResultsList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search spaces',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty && _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_joinError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _joinError!,
              style: TextStyle(color: cs.error),
            ),
          ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildResultsList() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 200) {
          unawaited(_loadMore());
        }
        return false;
      },
      child: ListView.builder(
        itemCount: _results!.length + (_hasSentinel ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _results!.length) return _buildSentinel();
          final chunk = _results![i];
          final name = chunk.name ?? chunk.canonicalAlias ?? chunk.roomId;
          return ListTile(
            leading: _avatarFor(
              chunk.avatarUrl?.toString() ?? '',
              name,
              size: 40,
            ),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${chunk.numJoinedMembers} members'),
            onTap: () => _openPreview(chunk),
          );
        },
      ),
    );
  }

  // ── Preview view ────────────────────────────────────────────────

  Widget _buildPreview(_PreviewFrame frame) {
    final cs = Theme.of(context).colorScheme;

    if (frame.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              frame.error!,
              style: TextStyle(color: cs.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => _retryHierarchy(frame),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (frame.hierarchy == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    final rooms = frame.hierarchy!.rooms;
    if (rooms.isEmpty) {
      return Center(
        child: Text(
          'No data for this space.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final self = rooms.first;
    final children = rooms.skip(1).toList();

    return Column(
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
        _buildPreviewHeader(self, children.length),
        const Divider(height: 24),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'This space has no rooms yet.',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          )
        else
          Text(
            'Rooms in this space',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: children.length,
            itemBuilder: (_, i) => _buildChildTile(children[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewHeader(SpaceRoomsChunk$2 self, int childCount) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final name = self.name ?? self.canonicalAlias ?? self.roomId;
    final alreadyMember = _isMember(self.roomId);
    final isJoiningSelf = _joiningRoomId == self.roomId;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avatarFor(self.avatarUrl?.toString() ?? '', name, size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (self.canonicalAlias != null)
                Text(
                  self.canonicalAlias!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              Text(
                '${self.numJoinedMembers} members · '
                '$childCount room${childCount == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (self.topic != null && self.topic!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  self.topic!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              if (alreadyMember)
                OutlinedButton.icon(
                  onPressed: _joiningRoomId != null
                      ? null
                      : () => _openExistingSpace(self.roomId),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open'),
                )
              else
                FilledButton(
                  onPressed: _joiningRoomId != null
                      ? null
                      : () => _joinChunk(
                            roomId: self.roomId,
                            alias: self.canonicalAlias,
                            via: _viaFromAlias(self.canonicalAlias),
                          ),
                  child: isJoiningSelf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Join space'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChildTile(SpaceRoomsChunk$2 child) {
    final cs = Theme.of(context).colorScheme;
    final name = child.name ?? child.canonicalAlias ?? child.roomId;
    final isSpace = child.roomType == 'm.space';
    final isJoining = _joiningRoomId == child.roomId;
    final alreadyJoined = _isMember(child.roomId);
    final disableOthers = _joiningRoomId != null && !isJoining;

    Widget trailing;
    if (isSpace) {
      trailing = OutlinedButton(
        onPressed:
            disableOthers ? null : () => _pushSubspace(child),
        child: const Text('Open'),
      );
    } else if (alreadyJoined) {
      trailing = Text(
        'Joined',
        style: TextStyle(color: cs.onSurfaceVariant),
      );
    } else if (isJoining) {
      trailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      trailing = FilledButton.tonal(
        onPressed: disableOthers
            ? null
            : () => _joinChunk(
                  roomId: child.roomId,
                  alias: child.canonicalAlias,
                  via: _viaFromAlias(child.canonicalAlias),
                ),
        child: const Text('Join'),
      );
    }

    return ListTile(
      leading: _avatarFor(
        child.avatarUrl?.toString() ?? '',
        name,
        size: 32,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${child.numJoinedMembers} members'),
      trailing: trailing,
    );
  }

  Widget _avatarFor(String mxc, String fallback, {required double size}) {
    final cs = Theme.of(context).colorScheme;
    final letter = fallback.isNotEmpty ? fallback[0].toUpperCase() : '?';

    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: cs.surfaceContainerHighest,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          height: 1,
        ),
      ),
    );

    if (mxc.isEmpty) {
      return ClipOval(child: placeholder);
    }

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: MxcImage(
          mxcUrl: mxc,
          client: widget.matrixService.client,
          fallbackText: letter,
          fallbackStyle: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
            height: 1,
          ),
          width: size,
          height: size,
        ),
      ),
    );
  }
}

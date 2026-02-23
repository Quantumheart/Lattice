import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:matrix/matrix.dart';
import '../services/matrix_service.dart';

// ── New Room dialog ───────────────────────────────────────────

class NewRoomDialog extends StatefulWidget {
  const NewRoomDialog._({required this.matrixService});

  final MatrixService matrixService;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
  }) {
    return showDialog(
      context: context,
      builder: (_) => NewRoomDialog._(matrixService: matrixService),
    );
  }

  @override
  State<NewRoomDialog> createState() => _NewRoomDialogState();
}

class _NewRoomDialogState extends State<NewRoomDialog> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  final _inviteController = TextEditingController();
  final _inviteFocusNode = FocusNode();
  bool _isPublic = false;
  bool _enableEncryption = true;
  bool _loading = false;
  bool _inviteSearching = false;
  String? _nameError;
  String? _networkError;
  final List<String> _invitedUsers = [];
  List<Profile> _inviteSearchResults = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _inviteFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    _inviteController.dispose();
    _inviteFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  static final _mxidRegex = RegExp(r'^@[^:]+:.+$');

  // ── Known contacts ──────────────────────────────────────────

  List<Profile> _knownContacts() {
    final rooms = widget.matrixService.client.rooms
        .where((r) => r.isDirectChat)
        .toList();
    final contacts = <Profile>[];
    for (final room in rooms) {
      final mxid = room.directChatMatrixID;
      if (mxid == null) continue;
      contacts.add(Profile(
        userId: mxid,
        displayName: room.getLocalizedDisplayname(),
        avatarUrl: room.avatar,
      ));
    }
    return contacts;
  }

  // ── Invite search ───────────────────────────────────────────

  void _onInviteSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _inviteSearchResults = [];
        _inviteSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchInviteDirectory(query.trim());
    });
  }

  Future<void> _searchInviteDirectory(String query) async {
    setState(() {
      _inviteSearching = true;
      _networkError = null;
    });

    try {
      final response = await widget.matrixService.client
          .searchUserDirectory(query, limit: 20);
      if (!mounted) return;
      setState(() {
        _inviteSearchResults = response.results;
        _inviteSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inviteSearching = false;
        _networkError = MatrixService.friendlyAuthError(e);
      });
    }
  }

  void _addInviteFromProfile(Profile profile) {
    final mxid = profile.userId;
    if (!_invitedUsers.contains(mxid)) {
      setState(() {
        _invitedUsers.add(mxid);
        _networkError = null;
      });
    }
    _inviteController.clear();
    setState(() => _inviteSearchResults = []);
  }

  void _addInvite() {
    final mxid = _inviteController.text.trim();
    if (mxid.isEmpty) return;
    if (!_mxidRegex.hasMatch(mxid)) {
      setState(() => _networkError = 'Invalid Matrix ID (use @user:server)');
      return;
    }
    if (_invitedUsers.contains(mxid)) {
      _inviteController.clear();
      return;
    }
    setState(() {
      _invitedUsers.add(mxid);
      _networkError = null;
    });
    _inviteController.clear();
    setState(() => _inviteSearchResults = []);
  }

  void _removeInvite(String userId) {
    setState(() => _invitedUsers.remove(userId));
  }

  // ── Invite suggestions list ─────────────────────────────────

  List<Widget> _inviteSuggestions(ColorScheme cs) {
    final query = _inviteController.text.trim();
    final profiles = query.isEmpty ? _knownContacts() : _inviteSearchResults;
    final filtered =
        profiles.where((p) => !_invitedUsers.contains(p.userId)).toList();
    if (filtered.isEmpty) return [];

    final tiles = <Widget>[];
    if (query.isEmpty && filtered.isNotEmpty) {
      tiles.add(Padding(
        padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
        child: Text(
          'Recent contacts',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ));
    }
    for (final p in filtered) {
      tiles.add(ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: cs.primaryContainer,
          child: Text(
            (p.displayName ?? p.userId).characters.first.toUpperCase(),
            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
          ),
        ),
        title: Text(p.displayName ?? p.userId,
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        subtitle: p.displayName != null
            ? Text(p.userId,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis)
            : null,
        onTap: () => _addInviteFromProfile(p),
      ));
    }
    return tiles;
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
        visibility: _isPublic ? Visibility.public : Visibility.private,
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
        invite: _invitedUsers.isNotEmpty ? _invitedUsers : null,
      );

      await client.waitForRoomInSync(roomId, join: true);

      if (!mounted) return;
      widget.matrixService.selectRoom(roomId);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _networkError = MatrixService.friendlyAuthError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('New Room'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
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
            const SizedBox(height: 16),
            TextField(
              controller: _inviteController,
              focusNode: _inviteFocusNode,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: 'Invite users (optional)',
                hintText: '@user:server.com or display name',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _loading ? null : _addInvite,
                ),
              ),
              onChanged: _onInviteSearchChanged,
              onSubmitted: (_) => _addInvite(),
            ),
            if (_inviteSearching)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(),
              ),
            if (_inviteFocusNode.hasFocus && _inviteSuggestions(cs).isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: _inviteSuggestions(cs),
                ),
              ),
            if (_invitedUsers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _invitedUsers
                        .map((u) => Chip(
                              label: Text(u, style: const TextStyle(fontSize: 12)),
                              onDeleted: _loading ? null : () => _removeInvite(u),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Public room'),
              value: _isPublic,
              onChanged:
                  _loading ? null : (v) => setState(() => _isPublic = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Enable encryption'),
              value: _enableEncryption,
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _enableEncryption = v),
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

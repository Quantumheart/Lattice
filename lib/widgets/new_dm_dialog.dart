import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../services/matrix_service.dart';

// ── New Direct Message dialog ─────────────────────────────────

class NewDirectMessageDialog extends StatefulWidget {
  const NewDirectMessageDialog._({required this.matrixService});

  final MatrixService matrixService;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
  }) {
    return showDialog(
      context: context,
      builder: (_) => NewDirectMessageDialog._(matrixService: matrixService),
    );
  }

  @override
  State<NewDirectMessageDialog> createState() =>
      _NewDirectMessageDialogState();
}

class _NewDirectMessageDialogState extends State<NewDirectMessageDialog> {
  final _searchController = TextEditingController();
  bool _loading = false;
  bool _searching = false;
  String? _networkError;
  List<Profile> _searchResults = [];
  Timer? _debounce;

  static final _mxidRegex = RegExp(r'^@[^:]+:.+$');

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Known contacts ──────────────────────────────────────────

  List<_Contact> _knownContacts() {
    final rooms = widget.matrixService.client.rooms
        .where((r) => r.isDirectChat)
        .toList();
    final contacts = <_Contact>[];
    for (final room in rooms) {
      final mxid = room.directChatMatrixID;
      if (mxid == null) continue;
      contacts.add(_Contact(
        userId: mxid,
        displayName: room.getLocalizedDisplayname(),
        avatarUrl: room.avatar,
      ));
    }
    return contacts;
  }

  // ── Search ──────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() {}); // Rebuild to update button state
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchDirectory(query.trim());
    });
  }

  Future<void> _searchDirectory(String query) async {
    setState(() {
      _searching = true;
      _networkError = null;
    });

    try {
      final response = await widget.matrixService.client
          .searchUserDirectory(query, limit: 20);
      if (!mounted) return;
      setState(() {
        _searchResults = response.results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _networkError = MatrixService.friendlyAuthError(e);
      });
    }
  }

  // ── Start DM ────────────────────────────────────────────────

  Future<void> _startChat(String userId) async {
    setState(() {
      _loading = true;
      _networkError = null;
    });

    try {
      final client = widget.matrixService.client;
      final roomId = await client.startDirectChat(
        userId,
        enableEncryption: true,
      );
      // Only wait if the room isn't already synced (existing DMs return
      // immediately and would hang waitForRoomInSync forever).
      if (client.getRoomById(roomId) == null) {
        await client.waitForRoomInSync(roomId, join: true);
      }

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

  void _submitFromField() {
    final text = _searchController.text.trim();
    if (_mxidRegex.hasMatch(text)) {
      _startChat(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _searchController.text.trim();
    final contacts = _knownContacts();
    final showContacts = query.isEmpty && _searchResults.isEmpty;
    final isValidMxid = _mxidRegex.hasMatch(query);

    return AlertDialog(
      title: const Text('New Direct Message'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Search users',
                hintText: '@user:server.com or display name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _submitFromField(),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (showContacts && contacts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recent contacts',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: contacts.length,
                  itemBuilder: (context, i) {
                    final c = contacts[i];
                    return _UserTile(
                      displayName: c.displayName,
                      userId: c.userId,
                      avatarUrl: c.avatarUrl,
                      loading: _loading,
                      onTap: () => _startChat(c.userId),
                    );
                  },
                ),
              ),
            ],
            if (!showContacts && _searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, i) {
                    final p = _searchResults[i];
                    return _UserTile(
                      displayName: p.displayName,
                      userId: p.userId,
                      avatarUrl: p.avatarUrl,
                      loading: _loading,
                      onTap: () => _startChat(p.userId),
                    );
                  },
                ),
              ),
            ],
            if (_networkError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _networkError!,
                  style: TextStyle(color: cs.error, fontSize: 13),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: CircularProgressIndicator(strokeWidth: 2.5),
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
          onPressed: _loading || !isValidMxid ? null : _submitFromField,
          child: const Text('Start Chat'),
        ),
      ],
    );
  }
}

// ── User tile ─────────────────────────────────────────────────

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.displayName,
    required this.userId,
    this.avatarUrl,
    required this.loading,
    required this.onTap,
  });

  final String? displayName;
  final String userId;
  final Uri? avatarUrl;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      enabled: !loading,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: cs.primaryContainer,
        child: Text(
          (displayName ?? userId).characters.first.toUpperCase(),
          style: TextStyle(color: cs.onPrimaryContainer, fontSize: 14),
        ),
      ),
      title: Text(displayName ?? userId, overflow: TextOverflow.ellipsis),
      subtitle: displayName != null
          ? Text(userId,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis)
          : null,
      onTap: onTap,
    );
  }
}

// ── Contact model ─────────────────────────────────────────────

class _Contact {
  const _Contact({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final Uri? avatarUrl;
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../services/matrix_service.dart';
import '../widgets/room_avatar.dart';
import '../widgets/room_details_panel.dart';
import '../widgets/message_bubble.dart';
import '../widgets/user_avatar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.roomId,
    this.onBack,
    this.onShowDetails,
  });

  final String roomId;

  /// On narrow layouts, called to pop back to room list.
  final VoidCallback? onBack;

  /// On desktop, called to toggle the room details side panel.
  final VoidCallback? onShowDetails;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _itemScrollCtrl = ItemScrollController();
  final _itemPosListener = ItemPositionsListener.create();
  Timeline? _timeline;
  StreamSubscription? _timelineSub;
  bool _loadingHistory = false;

  // ── Search state ──────────────────────────────────────────
  bool _isSearching = false;
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<Event> _searchResults = [];
  String? _searchNextBatch;
  bool _isSearchLoading = false;
  String? _searchError;
  Timer? _debounceTimer;
  String? _highlightedEventId;
  static const _searchBatchLimit = 500;
  static const _minQueryLength = 3;
  static const _debounceDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _initTimeline();
    _itemPosListener.itemPositions.addListener(_onScroll);
  }

  Future<void> _initTimeline() async {
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    _timeline = await room.getTimeline(
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() {});
  }

  void _onScroll() {
    final positions = _itemPosListener.itemPositions.value;
    if (positions.isEmpty) return;
    final maxIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    final events = _timeline?.events
            .where((e) =>
                e.type == EventTypes.Message || e.type == EventTypes.Encrypted)
            .toList() ??
        [];
    if (maxIndex >= events.length - 3 && !_loadingHistory) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_timeline == null || !_timeline!.canRequestHistory || _loadingHistory) {
      return;
    }
    _loadingHistory = true;
    try {
      await _timeline!.requestHistory();
    } finally {
      _loadingHistory = false;
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final scaffold = ScaffoldMessenger.of(context);
    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    try {
      await room.sendTextEvent(text);
    } catch (e) {
      _msgCtrl.text = text;
      scaffold.showSnackBar(
        SnackBar(content: Text('Failed to send: ${MatrixService.friendlyAuthError(e)}')),
      );
    }
  }

  // ── Search methods ────────────────────────────────────────

  void _openSearch() {
    setState(() {
      _isSearching = true;
      _searchResults = [];
      _searchNextBatch = null;
      _searchError = null;
    });
    // Delay focus request to after the frame builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _debounceTimer?.cancel();
    _searchCtrl.clear();
    setState(() {
      _isSearching = false;
      _searchResults = [];
      _searchNextBatch = null;
      _isSearchLoading = false;
      _searchError = null;
    });
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().length < _minQueryLength) {
      setState(() {
        _searchResults = [];
        _searchNextBatch = null;
        _searchError = null;
      });
      return;
    }
    // Rebuild to show/hide close button immediately.
    setState(() {});
    _debounceTimer = Timer(_debounceDuration, () {
      _performSearch();
    });
  }

  Future<void> _performSearch({bool loadMore = false}) async {
    final query = _searchCtrl.text.trim();
    if (query.length < _minQueryLength) return;

    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;

    setState(() {
      _isSearchLoading = true;
      _searchError = null;
      if (!loadMore) {
        _searchResults = [];
        _searchNextBatch = null;
      }
    });

    try {
      debugPrint('[Lattice] Searching room for: $query');
      final result = await room.searchEvents(
        searchTerm: query,
        limit: _searchBatchLimit,
        nextBatch: loadMore ? _searchNextBatch : null,
      );

      if (!mounted) return;

      setState(() {
        if (loadMore) {
          _searchResults.addAll(result.events);
        } else {
          _searchResults = result.events.toList();
        }
        _searchNextBatch = result.nextBatch;
        _isSearchLoading = false;
      });
    } catch (e) {
      debugPrint('[Lattice] Search error: $e');
      if (!mounted) return;
      setState(() {
        _isSearchLoading = false;
        _searchError = 'Search failed. Please try again.';
      });
    }
  }

  void _scrollToEvent(Event event) {
    _closeSearch();

    // Find the event in the current timeline.
    final events = _timeline?.events
            .where((e) =>
                e.type == EventTypes.Message || e.type == EventTypes.Encrypted)
            .toList() ??
        [];

    final index = events.indexWhere((e) => e.eventId == event.eventId);
    if (index == -1) {
      debugPrint('[Lattice] Event not in loaded timeline: ${event.eventId}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message not in loaded history'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() => _highlightedEventId = event.eventId);

    // Scroll to the target message by index. Post-frame callback is needed
    // because _closeSearch() triggers a rebuild that remounts the list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemScrollCtrl.isAttached) {
        _itemScrollCtrl.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });

    // Clear highlight after a delay.
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _highlightedEventId = null);
      }
    });
  }

  @override
  void dispose() {
    _itemPosListener.itemPositions.removeListener(_onScroll);
    _msgCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    _timelineSub?.cancel();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (room == null) {
      return Scaffold(
        body: Center(child: Text('Room not found', style: tt.bodyLarge)),
      );
    }

    final events = _timeline?.events
            .where((e) =>
                e.type == EventTypes.Message || e.type == EventTypes.Encrypted)
            .toList() ??
        [];

    return Scaffold(
      appBar: _isSearching
          ? _buildSearchAppBar(cs, tt)
          : _buildDefaultAppBar(room, tt),
      body: _isSearching
          ? _buildSearchBody(cs, tt)
          : _buildChatBody(events, matrix, cs, tt),
    );
  }

  // ── Default app bar ───────────────────────────────────────

  AppBar _buildDefaultAppBar(Room room, TextTheme tt) {
    return AppBar(
      leading: widget.onBack != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: widget.onBack,
            )
          : null,
      automaticallyImplyLeading: false,
      titleSpacing: widget.onBack != null ? 0 : 16,
      title: Row(
        children: [
          RoomAvatarWidget(room: room, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.getLocalizedDisplayname(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium,
                ),
                Text(
                  _memberCountLabel(room),
                  style: tt.bodyMedium?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          onPressed: _openSearch,
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: () {
            if (widget.onShowDetails != null) {
              widget.onShowDetails!();
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RoomDetailsPanel(
                    roomId: widget.roomId,
                    isFullPage: true,
                  ),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  // ── Search app bar ────────────────────────────────────────

  AppBar _buildSearchAppBar(ColorScheme cs, TextTheme tt) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _closeSearch,
      ),
      titleSpacing: 0,
      title: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocusNode,
        onChanged: _onSearchChanged,
        style: tt.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search messages…',
          border: InputBorder.none,
          hintStyle: tt.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      actions: [
        if (_searchCtrl.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              _searchCtrl.clear();
              _onSearchChanged('');
              _searchFocusNode.requestFocus();
            },
          ),
      ],
    );
  }

  // ── Chat body (messages + compose) ────────────────────────

  Widget _buildChatBody(
      List<Event> events, MatrixService matrix, ColorScheme cs, TextTheme tt) {
    return Column(
      children: [
        // ── Messages ──
        Expanded(
          child: _timeline == null
              ? const Center(child: CircularProgressIndicator())
              : events.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet.\nSay hello!',
                        textAlign: TextAlign.center,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : ScrollablePositionedList.builder(
                      itemScrollController: _itemScrollCtrl,
                      itemPositionsListener: _itemPosListener,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: events.length,
                      itemBuilder: (context, i) {
                        final event = events[i];
                        final isMe = event.senderId == matrix.client.userID;

                        // Group consecutive messages from same sender.
                        final prevSender = i + 1 < events.length
                            ? events[i + 1].senderId
                            : null;
                        final isFirst = event.senderId != prevSender;

                        return MessageBubble(
                          event: event,
                          isMe: isMe,
                          isFirst: isFirst,
                          highlighted: event.eventId == _highlightedEventId,
                        );
                      },
                    ),
        ),

        // ── Compose bar ──
        _ComposeBar(
          controller: _msgCtrl,
          onSend: _send,
        ),
      ],
    );
  }

  // ── Search body (results list) ────────────────────────────

  Widget _buildSearchBody(ColorScheme cs, TextTheme tt) {
    final query = _searchCtrl.text.trim();

    // Not enough characters yet.
    if (query.length < _minQueryLength) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Type at least $_minQueryLength characters to search',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Error state.
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: cs.error.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              Text(
                _searchError!,
                style: tt.bodyMedium?.copyWith(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Loading first batch.
    if (_isSearchLoading && _searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Empty results.
    if (_searchResults.isEmpty && !_isSearchLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'No messages found for "$query"',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Results list.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _searchResults.length + (_searchNextBatch != null ? 1 : 0),
      itemBuilder: (context, i) {
        // "Load more" button at the end.
        if (i == _searchResults.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _isSearchLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: () => _performSearch(loadMore: true),
                      child: const Text('Load more results'),
                    ),
            ),
          );
        }

        final event = _searchResults[i];
        return _SearchResultTile(
          event: event,
          query: query,
          onTap: () => _scrollToEvent(event),
        );
      },
    );
  }

  String _memberCountLabel(Room room) {
    final count = room.summary.mJoinedMemberCount ?? 0;
    if (count == 0) return '';
    if (count == 1) return '1 member';
    return '$count members';
  }
}

// ── Search result tile ────────────────────────────────────────

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.event,
    required this.query,
    required this.onTap,
  });

  final Event event;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final senderName =
        event.senderFromMemoryOrFallback.displayName ?? event.senderId;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender avatar
            UserAvatar(
              client: event.room.client,
              avatarUrl: event.senderFromMemoryOrFallback.avatarUrl,
              userId: event.senderId,
              size: 36,
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name + timestamp
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _formatTimestamp(event.originServerTs),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),

                  // Message body with highlighted query
                  _buildHighlightedBody(tt, cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedBody(TextTheme tt, ColorScheme cs) {
    final body = event.body;
    final spans = _highlightSpans(body, query);

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: tt.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        children: spans.map((span) {
          if (span.isMatch) {
            return TextSpan(
              text: span.text,
              style: TextStyle(
                backgroundColor: cs.primaryContainer,
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            );
          }
          return TextSpan(text: span.text);
        }).toList(),
      ),
    );
  }

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 24) {
      final h = ts.hour.toString().padLeft(2, '0');
      final m = ts.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}';
  }
}

// ── Highlighted text helpers ──────────────────────────────────

class _HighlightSpan {
  const _HighlightSpan(this.text, this.isMatch);
  final String text;
  final bool isMatch;
}

List<_HighlightSpan> _highlightSpans(String text, String query) {
  if (query.isEmpty) return [_HighlightSpan(text, false)];

  final lower = text.toLowerCase();
  final queryLower = query.toLowerCase();
  final spans = <_HighlightSpan>[];
  var start = 0;

  while (start < text.length) {
    final index = lower.indexOf(queryLower, start);
    if (index == -1) {
      spans.add(_HighlightSpan(text.substring(start), false));
      break;
    }
    if (index > start) {
      spans.add(_HighlightSpan(text.substring(start, index), false));
    }
    spans
        .add(_HighlightSpan(text.substring(index, index + query.length), true));
    start = index + query.length;
  }

  return spans;
}

// ── Compose bar ───────────────────────────────────────────────

class _ComposeBar extends StatelessWidget {
  const _ComposeBar({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 8,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: cs.onSurfaceVariant),
            onPressed: () {
              // TODO: attachment picker
            },
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
              minLines: 1,
              maxLines: 5,
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            onPressed: onSend,
            icon: const Icon(Icons.send_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:kohera/features/chat/widgets/call_event_tile.dart';
import 'package:kohera/features/chat/widgets/chat_message_item.dart';
import 'package:kohera/features/chat/widgets/read_receipts.dart';
import 'package:kohera/features/chat/widgets/state_event_tile.dart';
import 'package:kohera/features/chat/widgets/sticker_bubble.dart';
import 'package:kohera/features/chat/widgets/unread_divider.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class MessageListView extends StatefulWidget {
  const MessageListView({
    required this.room,
    required this.matrix,
    required this.onReply,
    required this.onEdit,
    required this.onToggleReaction,
    required this.onPin,
    required this.onHighlight,
    this.initialEventId,
    this.highlightedEventId,
    this.onScrollBack,
    super.key,
  });

  final Room room;
  final MatrixService matrix;
  final String? initialEventId;
  final String? highlightedEventId;
  final void Function(Event event) onReply;
  final void Function(Event event, Timeline? timeline) onEdit;
  final Future<void> Function(Event event, String emoji) onToggleReaction;
  final Future<void> Function(Event event) onPin;
  final void Function(String eventId) onHighlight;
  final VoidCallback? onScrollBack;

  @override
  State<MessageListView> createState() => MessageListViewState();
}

class MessageListViewState extends State<MessageListView> {
  static const _historyLoadThreshold = 15;
  static const _scrollAnimationDuration = Duration(milliseconds: 400);
  static const _readMarkerDelay = Duration(seconds: 1);

  static const _scrollBackDismissThreshold = 120.0;

  final _itemScrollCtrl = ItemScrollController();
  final _itemPosListener = ItemPositionsListener.create();
  Timeline? _timeline;
  bool _loadingHistory = false;
  Timer? _readMarkerTimer;
  int _initGeneration = 0;
  List<Event>? _cachedVisibleEvents;
  String? _initialFullyReadId;
  double _scrollBackDelta = 0;
  bool _scrollBackFired = false;

  Timeline? get timeline => _timeline;

  @override
  void initState() {
    super.initState();
    _itemPosListener.itemPositions.addListener(_onScroll);
    unawaited(_initTimeline());
  }

  @override
  void didUpdateWidget(MessageListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id ||
        oldWidget.initialEventId != widget.initialEventId) {
      _timeline?.cancelSubscriptions();
      _readMarkerTimer?.cancel();
      _cachedVisibleEvents = null;
      unawaited(_initTimeline());
    }
  }

  // ── Timeline ───────────────────────────────────────────

  Future<void> _initTimeline() async {
    final gen = ++_initGeneration;
    final snapshotFullyRead = widget.room.fullyRead;
    _initialFullyReadId =
        snapshotFullyRead.isNotEmpty ? snapshotFullyRead : null;
    _timeline = await widget.room.getTimeline(
      eventContextId: widget.initialEventId,
      onUpdate: () {
        if (mounted) {
          _cachedVisibleEvents = null;
          setState(() {});
        }
        _markAsRead();
      },
    );
    if (gen != _initGeneration) return;
    if (mounted) setState(() {});
    _markAsRead();
    _requestMissingKeys();
    if (widget.initialEventId != null) _jumpToEvent(widget.initialEventId!);
    await _autoPaginateUntilVisible(gen);
  }

  Future<void> _autoPaginateUntilVisible(int gen) async {
    const maxRounds = 5;
    var rounds = 0;
    while (mounted &&
        gen == _initGeneration &&
        _visibleEvents.isEmpty &&
        (_timeline?.events.isNotEmpty ?? false) &&
        (_timeline?.canRequestHistory ?? false) &&
        rounds < maxRounds) {
      rounds++;
      await _loadMore();
    }
  }

  void _requestMissingKeys() {
    final encryption = widget.room.client.encryption;
    if (encryption == null) return;

    final events = _timeline?.events;
    if (events == null) return;

    final requested = <String>{};
    for (final event in events) {
      if (event.type == EventTypes.Encrypted &&
          event.messageType == MessageTypes.BadEncrypted) {
        final sessionId = event.content.tryGet<String>('session_id');
        final senderKey = event.content.tryGet<String>('sender_key');
        if (sessionId != null && requested.add(sessionId)) {
          unawaited(
            encryption.keyManager.loadSingleKey(widget.room.id, sessionId).catchError(
              (Object e) {
                debugPrint('[Kohera] Key load failed for $sessionId: $e');
              },
            ),
          );
          if (senderKey != null) {
            try {
              encryption.keyManager.maybeAutoRequest(
                widget.room.id,
                sessionId,
                senderKey,
              );
            } catch (e) {
              debugPrint('[Kohera] P2P key request failed for $sessionId: $e');
            }
          }
        }
      }
    }
  }

  List<Event> get _visibleEvents {
    if (_cachedVisibleEvents != null) return _cachedVisibleEvents!;
    final events = _timeline?.events;
    if (events == null) return [];
    _cachedVisibleEvents = events
        .where((e) =>
            ((e.type == EventTypes.Message || e.type == EventTypes.Encrypted) &&
                e.relationshipType != RelationshipTypes.edit &&
                !_isCallMemberEvent(e)) ||
            callEventTypes.contains(e.type) ||
            _isStateEvent(e) ||
            e.type == EventTypes.Sticker,)
        .toList();
    return _cachedVisibleEvents!;
  }

  void _markAsRead() {
    _readMarkerTimer?.cancel();
    _readMarkerTimer = Timer(_readMarkerDelay, () async {
      if (!mounted) return;
      final lastEvent = widget.room.lastEvent;
      if (lastEvent != null && widget.room.notificationCount > 0) {
        try {
          final sendPublic = context.read<PreferencesService>().readReceipts;
          await widget.room.setReadMarker(
            lastEvent.eventId,
            mRead: sendPublic ? lastEvent.eventId : null,
          );
        } catch (e) {
          debugPrint('[Kohera] Failed to mark as read: $e');
        }
      }
    });
  }

  // ── Scroll & history ───────────────────────────────────

  void _onScroll() {
    final positions = _itemPosListener.itemPositions.value;
    if (positions.isEmpty) return;
    final maxIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    if (maxIndex >= _visibleEvents.length - _historyLoadThreshold && !_loadingHistory) {
      unawaited(_loadMore());
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (widget.onScrollBack == null) return false;
    if (notification is ScrollStartNotification) {
      _scrollBackDelta = 0;
      _scrollBackFired = false;
    } else if (notification is ScrollUpdateNotification) {
      _scrollBackDelta += notification.scrollDelta ?? 0;
      if (!_scrollBackFired &&
          _scrollBackDelta >= _scrollBackDismissThreshold) {
        _scrollBackFired = true;
        widget.onScrollBack!.call();
      }
    }
    return false;
  }

  Future<void> _loadMore() async {
    if (_timeline == null || !_timeline!.canRequestHistory || _loadingHistory) {
      return;
    }
    setState(() => _loadingHistory = true);
    try {
      while (mounted && _timeline!.canRequestHistory) {
        await _timeline!.requestHistory();
        _cachedVisibleEvents = null;
        final positions = _itemPosListener.itemPositions.value;
        if (positions.isEmpty) break;
        final maxIndex =
            positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
        if (maxIndex < _visibleEvents.length - _historyLoadThreshold) break;
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to load history: $e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // ── Navigation ─────────────────────────────────────────

  void navigateToEvent(Event event) {
    unawaited(_navigateToEvent(event));
  }

  Future<void> _navigateToEvent(Event event) async {
    final index = _visibleEvents.indexWhere((e) => e.eventId == event.eventId);
    if (index == -1) {
      debugPrint(
        '[Kohera] Event not in loaded timeline, reloading: ${event.eventId}',
      );
      await _reloadTimelineAt(event.eventId);
      return;
    }
    _scrollToIndex(index, event.eventId);
  }

  Future<void> _reloadTimelineAt(String eventId) async {
    _timeline?.cancelSubscriptions();
    _cachedVisibleEvents = null;
    setState(() => _timeline = null);

    final gen = ++_initGeneration;
    _timeline = await widget.room.getTimeline(
      eventContextId: eventId,
      onUpdate: () {
        if (mounted) {
          _cachedVisibleEvents = null;
          setState(() {});
        }
        _markAsRead();
      },
    );
    if (gen != _initGeneration || !mounted) return;
    setState(() {});
    _jumpToEvent(eventId);
  }

  void _jumpToEvent(String eventId) {
    final index = _visibleEvents.indexWhere((e) => e.eventId == eventId);
    if (index == -1) {
      debugPrint('[Kohera] Event not found after context load: $eventId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load the target message'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _scrollToIndex(index, eventId);
  }

  void _scrollToIndex(int index, String eventId) {
    widget.onHighlight(eventId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemScrollCtrl.isAttached) {
        unawaited(
          _itemScrollCtrl.scrollTo(
            index: index,
            duration: _scrollAnimationDuration,
            curve: Curves.easeInOut,
            alignment: 0.5,
          ),
        );
      }
    });
  }

  // ── Helpers ────────────────────────────────────────────

  static bool _isCallEvent(Event event) => callEventTypes.contains(event.type);

  static bool _isStateEvent(Event event) {
    if (event.type == EventTypes.RoomName ||
        event.type == EventTypes.RoomTopic ||
        event.type == EventTypes.RoomAvatar ||
        event.type == EventTypes.RoomTombstone) {
      return true;
    }
    if (event.type == EventTypes.RoomMember) {
      return !_isNoOpMemberEvent(event);
    }
    return false;
  }

  static bool _isNoOpMemberEvent(Event event) {
    final prev = event.prevContent;
    if (prev == null) return false;
    final curr = event.content;
    final prevMembership = prev.tryGet<String>('membership');
    final currMembership = curr.tryGet<String>('membership');
    if (prevMembership != currMembership) return false;
    if (prev.tryGet<String>('displayname') !=
        curr.tryGet<String>('displayname')) {
      return false;
    }
    if (prev.tryGet<String>('avatar_url') !=
        curr.tryGet<String>('avatar_url')) {
      return false;
    }
    return true;
  }

  static bool _isCallMemberEvent(Event event) =>
      event.type == kCallMember ||
      event.type == kCallMemberMsc ||
      event.body.contains(kCallMember) ||
      event.body.contains(kCallMemberMsc);

  Duration? _callDuration(Event event) {
    if (event.type != kCallHangup) return null;
    final reason = event.content.tryGet<String>('reason');
    if (reason == 'invite_timeout') return null;

    final hangupCallId = event.content.tryGet<String>('call_id');
    final events = _timeline?.events;
    if (events == null) return null;

    Event? matchedInvite;
    for (final e in events) {
      if (e.type != kCallInvite) continue;
      if (!e.originServerTs.isBefore(event.originServerTs)) continue;
      if (hangupCallId != null &&
          hangupCallId.isNotEmpty &&
          e.content.tryGet<String>('call_id') == hangupCallId) {
        matchedInvite = e;
        break;
      }
      matchedInvite ??= e;
    }

    if (matchedInvite == null) return null;
    final d = event.originServerTs.difference(matchedInvite.originServerTs);
    if (d.isNegative || d.inHours >= 24) return null;
    return d;
  }

  @override
  void dispose() {
    _itemPosListener.itemPositions.removeListener(_onScroll);
    _readMarkerTimer?.cancel();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_timeline == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final events = _visibleEvents;
    if (events.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      final tt = Theme.of(context).textTheme;
      return Center(
        child: Text(
          'No messages yet.\nSay hello!',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final isMobile = isTouchDevice;
    final showReceipts = context.watch<PreferencesService>().readReceipts;
    final receiptMap = showReceipts
        ? buildReceiptMap(widget.room, widget.matrix.client.userID)
        : <String, List<Receipt>>{};
    final hasLoadingIndicator = _loadingHistory;
    final totalCount = events.length + (hasLoadingIndicator ? 1 : 0);

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollCtrl,
        itemPositionsListener: _itemPosListener,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: totalCount,
        itemBuilder: (context, i) {
          if (hasLoadingIndicator && i == totalCount - 1) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final event = events[i];

          final Widget tile;
          if (_isCallEvent(event)) {
            tile = CallEventTile(
              event: event,
              isMe: event.senderId == widget.matrix.client.userID,
              duration: _callDuration(event),
            );
          } else if (_isStateEvent(event)) {
            tile = StateEventTile(event: event);
          } else if (event.type == EventTypes.Sticker) {
            tile = StickerBubble(
              event: event,
              isMe: event.senderId == widget.matrix.client.userID,
            );
          } else {
            final prevSender =
                i + 1 < events.length ? events[i + 1].senderId : null;
            tile = ChatMessageItem(
              event: event,
              isMe: event.senderId == widget.matrix.client.userID,
              isFirst: event.senderId != prevSender,
              isMobile: isMobile,
              timeline: _timeline,
              client: widget.matrix.client,
              highlightedEventId: widget.highlightedEventId,
              receiptMap: receiptMap,
              onReply: widget.onReply,
              onEdit: (event) => widget.onEdit(event, _timeline),
              onToggleReaction: widget.onToggleReaction,
              onPin: widget.onPin,
              onTapReply: _navigateToEvent,
            );
          }

          if (_shouldShowUnreadDivider(event, i, events)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tile,
                const UnreadDivider(),
              ],
            );
          }
          return tile;
        },
      ),
    );
  }

  bool _shouldShowUnreadDivider(
    Event event,
    int index,
    List<Event> events,
  ) {
    final markerId = _initialFullyReadId;
    if (markerId == null) return false;
    if (event.eventId != markerId) return false;
    if (index == 0) return false;
    return true;
  }
}

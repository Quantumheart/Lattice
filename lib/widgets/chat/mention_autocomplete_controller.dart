import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// The type of mention trigger detected in the compose bar.
enum MentionTriggerType { user, room }

/// A suggestion entry for the mention autocomplete overlay.
class MentionSuggestion {
  final MentionTriggerType type;

  /// For users: the display name. For rooms: the room name.
  final String displayName;

  /// For users: the MXID. For rooms: the canonical alias or room ID.
  final String id;

  /// The mxc:// avatar URI, if available.
  final Uri? avatarUrl;

  /// The Matrix [User] (for user mentions) or [Room] (for room mentions).
  final dynamic source;

  const MentionSuggestion({
    required this.type,
    required this.displayName,
    required this.id,
    this.avatarUrl,
    this.source,
  });
}

/// Encapsulates autocomplete state and logic for `@user` and `#room` mentions.
///
/// Listens to a [TextEditingController], detects trigger characters (`@` or `#`),
/// filters suggestions, and inserts the selected mention text.
class MentionAutocompleteController extends ChangeNotifier {
  MentionAutocompleteController({
    required this.textController,
    required this.room,
    required this.joinedRooms,
  }) {
    textController.addListener(_onTextChanged);
  }

  final TextEditingController textController;
  final Room room;
  final List<Room> joinedRooms;

  bool _isActive = false;
  MentionTriggerType? _triggerType;
  int _triggerOffset = -1;
  String _query = '';
  List<MentionSuggestion> _suggestions = [];
  int _selectedIndex = 0;

  /// Cached room members, loaded on first `@` trigger.
  List<User>? _cachedMembers;
  bool _loadingMembers = false;

  bool get isActive => _isActive;
  MentionTriggerType? get triggerType => _triggerType;
  String get query => _query;
  List<MentionSuggestion> get suggestions => _suggestions;
  int get selectedIndex => _selectedIndex;

  // ── Trigger detection ──────────────────────────────────────

  void _onTextChanged() {
    final text = textController.text;
    final selection = textController.selection;

    if (!selection.isValid || !selection.isCollapsed) {
      _dismiss();
      return;
    }

    final cursorPos = selection.baseOffset;
    if (cursorPos < 0 || cursorPos > text.length) {
      _dismiss();
      return;
    }

    // Walk backwards from cursor to find a trigger character.
    final textBeforeCursor = text.substring(0, cursorPos);
    final lastAt = textBeforeCursor.lastIndexOf('@');
    final lastHash = textBeforeCursor.lastIndexOf('#');

    int triggerPos = -1;
    MentionTriggerType? type;

    if (lastAt >= 0 && lastAt >= lastHash) {
      triggerPos = lastAt;
      type = MentionTriggerType.user;
    } else if (lastHash >= 0) {
      triggerPos = lastHash;
      type = MentionTriggerType.room;
    }

    if (triggerPos < 0 || type == null) {
      _dismiss();
      return;
    }

    // Trigger must be at start of text or preceded by whitespace.
    if (triggerPos > 0 && text[triggerPos - 1] != ' ' && text[triggerPos - 1] != '\n') {
      _dismiss();
      return;
    }

    // Query must not contain spaces (unless we want to support multi-word — keep simple).
    final queryText = text.substring(triggerPos + 1, cursorPos);

    // If there's a space in the query, the trigger is probably not active.
    if (queryText.contains(' ') || queryText.contains('\n')) {
      _dismiss();
      return;
    }

    _triggerOffset = triggerPos;
    _triggerType = type;
    _query = queryText;
    _isActive = true;
    _selectedIndex = 0;

    _updateSuggestions();
  }

  // ── Filtering ──────────────────────────────────────────────

  void _updateSuggestions() {
    if (_triggerType == MentionTriggerType.user) {
      _filterUsers();
    } else {
      _filterRooms();
    }
    notifyListeners();
  }

  void _filterUsers() {
    if (_cachedMembers == null && !_loadingMembers) {
      // Start with locally known members, then fetch full list.
      _cachedMembers = room.getParticipants();
      _loadingMembers = true;
      room.requestParticipants().then((members) {
        _cachedMembers = members;
        _loadingMembers = false;
        if (_isActive && _triggerType == MentionTriggerType.user) {
          _filterUsers();
          notifyListeners();
        }
      }).catchError((_) {
        _loadingMembers = false;
      });
    }

    final lowerQuery = _query.toLowerCase();
    _suggestions = _cachedMembers!
        .where((u) =>
            u.displayName != null &&
            u.displayName!.toLowerCase().contains(lowerQuery))
        .take(20)
        .map((u) => MentionSuggestion(
              type: MentionTriggerType.user,
              displayName: u.displayName ?? u.id,
              id: u.id,
              avatarUrl: u.avatarUrl,
              source: u,
            ))
        .toList();
  }

  void _filterRooms() {
    final lowerQuery = _query.toLowerCase();
    _suggestions = joinedRooms
        .where((r) =>
            r.getLocalizedDisplayname().toLowerCase().contains(lowerQuery))
        .take(20)
        .map((r) => MentionSuggestion(
              type: MentionTriggerType.room,
              displayName: r.getLocalizedDisplayname(),
              id: r.canonicalAlias.isNotEmpty ? r.canonicalAlias : r.id,
              avatarUrl: r.avatar,
              source: r,
            ))
        .toList();
  }

  // ── Keyboard navigation ────────────────────────────────────

  void moveUp() {
    if (_suggestions.isEmpty) return;
    _selectedIndex =
        (_selectedIndex - 1).clamp(0, _suggestions.length - 1);
    notifyListeners();
  }

  void moveDown() {
    if (_suggestions.isEmpty) return;
    _selectedIndex =
        (_selectedIndex + 1).clamp(0, _suggestions.length - 1);
    notifyListeners();
  }

  // ── Selection ──────────────────────────────────────────────

  /// Confirm the currently selected suggestion.
  void confirmSelection() {
    if (_suggestions.isEmpty) return;
    selectSuggestion(_suggestions[_selectedIndex]);
  }

  /// Insert the mention text for [suggestion], replacing the trigger + query.
  void selectSuggestion(MentionSuggestion suggestion) {
    final text = textController.text;
    final mentionText = _buildMentionText(suggestion);

    final before = text.substring(0, _triggerOffset);
    final cursorPos = textController.selection.baseOffset;
    final after = text.substring(cursorPos);

    final newText = '$before$mentionText$after';
    final newCursor = before.length + mentionText.length;

    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );

    _dismiss();
  }

  String _buildMentionText(MentionSuggestion suggestion) {
    if (suggestion.type == MentionTriggerType.user) {
      final name = suggestion.displayName;
      // Use bracket syntax for names with spaces or special characters.
      final needsBrackets = name.contains(' ') || name.contains(RegExp(r'[^\w.-]'));
      return needsBrackets ? '@[$name] ' : '@$name ';
    } else {
      // Room mention: use canonical alias if available.
      if (suggestion.id.startsWith('#')) {
        return '${suggestion.id} ';
      }
      return '#${suggestion.displayName} ';
    }
  }

  // ── Dismissal ──────────────────────────────────────────────

  void dismiss() => _dismiss();

  void _dismiss() {
    if (!_isActive) return;
    _isActive = false;
    _triggerType = null;
    _triggerOffset = -1;
    _query = '';
    _suggestions = [];
    _selectedIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    textController.removeListener(_onTextChanged);
    super.dispose();
  }
}

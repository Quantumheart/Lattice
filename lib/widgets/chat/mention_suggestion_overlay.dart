import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../room_avatar.dart';
import '../user_avatar.dart';
import 'mention_autocomplete_controller.dart';

/// Displays filtered mention suggestions above the compose bar text field.
class MentionSuggestionList extends StatelessWidget {
  const MentionSuggestionList({
    super.key,
    required this.controller,
    required this.client,
  });

  final MentionAutocompleteController controller;
  final Client client;

  static const _maxVisibleItems = 5;
  static const _maxHeight = 280.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final suggestions = controller.suggestions;

    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: suggestions.length.clamp(0, _maxVisibleItems),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          final isSelected = index == controller.selectedIndex;

          return _SuggestionTile(
            suggestion: suggestion,
            isSelected: isSelected,
            client: client,
            onTap: () => controller.selectSuggestion(suggestion),
          );
        },
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.isSelected,
    required this.client,
    required this.onTap,
  });

  final MentionSuggestion suggestion;
  final bool isSelected;
  final Client client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: isSelected
          ? cs.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _buildAvatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      suggestion.displayName,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      suggestion.id,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    if (suggestion.type == MentionTriggerType.room &&
        suggestion.roomId != null) {
      final room = client.getRoomById(suggestion.roomId!);
      if (room != null) {
        return RoomAvatarWidget(room: room, size: 32);
      }
    }
    return UserAvatar(
      client: client,
      avatarUrl: suggestion.avatarUrl,
      userId: suggestion.id,
      size: 32,
    );
  }
}

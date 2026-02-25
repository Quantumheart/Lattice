import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../services/chat_search_controller.dart';
import 'search_result_tile.dart';

/// Displays search results for in-room message search.
///
/// Shows contextual states: minimum query prompt, loading spinner,
/// error, empty results, or a scrollable results list.
class SearchResultsBody extends StatelessWidget {
  const SearchResultsBody({
    super.key,
    required this.search,
    required this.onTapResult,
  });

  final ChatSearchController search;
  final ValueChanged<Event> onTapResult;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final query = search.query;

    // Not enough characters yet.
    if (query.length < ChatSearchController.minQueryLength) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Type at least ${ChatSearchController.minQueryLength} characters to search',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Error state.
    if (search.error != null) {
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
                search.error!,
                style: tt.bodyMedium?.copyWith(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Loading first batch.
    if (search.isLoading && search.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Empty results.
    if (search.results.isEmpty && !search.isLoading) {
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
      itemCount: search.results.length + (search.nextBatch != null ? 1 : 0),
      itemBuilder: (context, i) {
        // "Load more" button at the end.
        if (i == search.results.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: search.isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: () => search.performSearch(loadMore: true),
                      child: const Text('Load more results'),
                    ),
            ),
          );
        }

        final event = search.results[i];
        return SearchResultTile(
          event: event,
          query: query,
          onTap: () => onTapResult(event),
        );
      },
    );
  }
}

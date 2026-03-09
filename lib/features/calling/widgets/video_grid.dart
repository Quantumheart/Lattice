import 'package:flutter/material.dart';
import 'package:lattice/features/calling/models/call_participant.dart';
import 'package:lattice/features/calling/widgets/participant_tile.dart';

class VideoGrid extends StatefulWidget {
  const VideoGrid({required this.participants, super.key});

  final List<CallParticipant> participants;

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _maxPerPage = 6;

  @override
  void didUpdateWidget(covariant VideoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pageCount = (widget.participants.length / _maxPerPage).ceil();
    if (_currentPage >= pageCount && pageCount > 0) {
      final clamped = pageCount - 1;
      _currentPage = clamped;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(clamped);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  (int columns, int rows) _computeGrid(int count, double width, double height) {
    final isLandscape = width > height;
    return switch (count) {
      0 => (0, 0),
      1 => (1, 1),
      2 => width > 720 ? (2, 1) : (1, 2),
      3 => isLandscape ? (3, 1) : (1, 3),
      4 => (2, 2),
      5 || 6 => isLandscape ? (3, 2) : (2, 3),
      _ => isLandscape ? (3, 2) : (2, 3),
    };
  }

  Widget _buildGrid(List<CallParticipant> participants, double width, double height) {
    if (participants.isEmpty) return const SizedBox.shrink();

    final (columns, rows) = _computeGrid(participants.length, width, height);

    return Column(
      children: List.generate(rows, (row) {
        return Expanded(
          child: Row(
            children: List.generate(columns, (col) {
              final i = row * columns + col;
              if (i < participants.length) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: ParticipantTile(participant: participants[i]),
                  ),
                );
              }
              return const Expanded(child: SizedBox.shrink());
            }),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.participants;

    if (participants.length <= _maxPerPage) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return _buildGrid(participants, constraints.maxWidth, constraints.maxHeight);
        },
      );
    }

    final pageCount = (participants.length / _maxPerPage).ceil();

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: pageCount,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, page) {
              final start = page * _maxPerPage;
              final end = (start + _maxPerPage).clamp(0, participants.length);
              final pageParticipants = participants.sublist(start, end);

              return LayoutBuilder(
                builder: (context, constraints) {
                  return _buildGrid(
                    pageParticipants,
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pageCount, (i) {
              return Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _currentPage
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.38),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

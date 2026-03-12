import 'package:flutter/material.dart';
import 'package:lattice/features/calling/models/call_participant.dart';
import 'package:lattice/features/calling/widgets/participant_tile.dart';

// coverage:ignore-start

class ScreenShareLayout extends StatelessWidget {
  const ScreenShareLayout({
    required this.screenSharer,
    required this.others,
    super.key,
  });

  final CallParticipant screenSharer;
  final List<CallParticipant> others;

  static const double _desktopBreakpoint = 1100;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        return isDesktop ? _buildHorizontal() : _buildVertical();
      },
    );
  }

  Widget _buildHorizontal() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: ParticipantTile(participant: screenSharer),
          ),
        ),
        if (others.isNotEmpty)
          Expanded(
            child: ListView.builder(
              itemCount: others.length,
              itemBuilder: (context, i) => AspectRatio(
                aspectRatio: 4 / 3,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: ParticipantTile(participant: others[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVertical() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: ParticipantTile(participant: screenSharer),
          ),
        ),
        if (others.isNotEmpty)
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: others.length,
              itemBuilder: (context, i) => AspectRatio(
                aspectRatio: 3 / 4,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: ParticipantTile(participant: others[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
// coverage:ignore-end

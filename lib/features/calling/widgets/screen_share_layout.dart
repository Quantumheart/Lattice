import 'package:flutter/material.dart';
import 'package:lattice/features/calling/models/call_participant.dart';
import 'package:lattice/features/calling/widgets/participant_tile.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

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
        return isDesktop ? _buildHorizontal(context) : _buildVertical(context);
      },
    );
  }

  Widget _buildScreenShareTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final track = screenSharer.screenShareTrack;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: cs.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (track != null)
              livekit.VideoTrackRenderer(track)
            else
              Center(
                child: Icon(Icons.screen_share, size: 48, color: cs.onSurface),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      cs.scrim.withValues(alpha: 0.54),
                    ],
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.screen_share,
                        size: 14,
                        color: cs.onInverseSurface,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          "${screenSharer.displayName}'s screen",
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onInverseSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontal(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: _buildScreenShareTile(context),
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

  Widget _buildVertical(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: _buildScreenShareTile(context),
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

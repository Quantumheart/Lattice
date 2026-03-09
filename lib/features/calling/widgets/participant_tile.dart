import 'package:flutter/material.dart';
import 'package:lattice/features/calling/models/call_participant.dart';

class ParticipantTile extends StatelessWidget {
  const ParticipantTile({required this.participant, super.key});

  final CallParticipant participant;

  static const _minAudioBarWidth = 4.0;
  static const _maxAudioBarWidth = 20.0;
  static const _audioLevelThreshold = 0.05;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: participant.isSpeaking ? cs.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: participant.isSpeaking
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoArea(context),
            _buildBottomOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (participant.isAudioOnly) {
      return ColoredBox(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: CircleAvatar(
            radius: 32,
            backgroundColor: cs.primaryContainer,
            child: Text(
              participant.displayName.isNotEmpty
                  ? participant.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontSize: 28,
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.videocam, size: 48, color: cs.onSurfaceVariant),
    );
  }

  Widget _buildBottomOverlay(BuildContext context) {
    final showAudioBar = participant.audioLevel > _audioLevelThreshold;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black54],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              if (showAudioBar) ...[
                Container(
                  width: _minAudioBarWidth +
                      participant.audioLevel *
                          (_maxAudioBarWidth - _minAudioBarWidth),
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  participant.isLocal
                      ? '${participant.displayName} (You)'
                      : participant.displayName,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (participant.isMuted)
                const Icon(Icons.mic_off, size: 14, color: Colors.redAccent),
            ],
          ),
        ),
      ),
    );
  }
}

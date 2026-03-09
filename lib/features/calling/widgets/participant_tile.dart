import 'package:flutter/material.dart';
import 'package:lattice/features/calling/models/call_participant.dart';

class ParticipantTile extends StatelessWidget {
  const ParticipantTile({required this.participant, super.key});

  final CallParticipant participant;

  Color _avatarColor() {
    const colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
    ];
    return colors[participant.id.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: participant.isSpeaking ? Colors.blue : Colors.transparent,
            width: 2,
          ),
          boxShadow: participant.isSpeaking
              ? [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
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
    if (participant.isAudioOnly) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: CircleAvatar(
            radius: 32,
            backgroundColor: _avatarColor(),
            child: Text(
              participant.displayName.isNotEmpty
                  ? participant.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.videocam, size: 48, color: Colors.white54),
      ),
    );
  }

  Widget _buildBottomOverlay(BuildContext context) {
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
              Container(
                width: participant.audioLevel * 20,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (participant.audioLevel > 0) const SizedBox(width: 4),
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
                const Icon(Icons.mic_off, size: 14, color: Colors.red),
            ],
          ),
        ),
      ),
    );
  }
}

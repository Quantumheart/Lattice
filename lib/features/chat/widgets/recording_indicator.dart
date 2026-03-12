import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lattice/core/utils/format_duration.dart';
import 'package:lattice/features/chat/services/voice_recording_controller.dart';

// coverage:ignore-start

class RecordingIndicator extends StatelessWidget {
  const RecordingIndicator({
    required this.controller, required this.onCancel, required this.onStop, super.key,
  });

  final VoiceRecordingController controller;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: onCancel,
                icon: Icon(Icons.close_rounded, color: cs.error),
              ),
              const _PulsingDot(),
              const SizedBox(width: 8),
              Text(
                formatDuration(controller.elapsed),
                style: tt.bodyMedium?.copyWith(
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recording…',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton.filled(
                onPressed: onStop,
                icon: const Icon(Icons.stop_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Pulsing red dot ───────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    unawaited(_anim.repeat(reverse: true));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.5 + _anim.value * 0.5),
          ),
        );
      },
    );
  }
}
// coverage:ignore-end

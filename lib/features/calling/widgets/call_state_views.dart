import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/shared/widgets/pulsing_avatar.dart';

// coverage:ignore-start

String formatCallElapsed(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

const _authenticatingPhrases = [
  'Cracking the mainframe...',
  'Punching through the firewall...',
  'Consulting the oracle...',
  'Unfurling the scroll...',
  'Inserting coin...',
  'Press START...',
  'Jacking in...',
  'Loading operator...',
  'Forging the keys...',
  'Decoding runes...',
];

const _connectingMediaPhrases = [
  'Spinning up the warp core...',
  'Weaving the portal...',
  'Loading level 1...',
  'Tracing the signal...',
  'Syncing ley lines...',
  'Spawning player...',
  'Aligning tachyons...',
  'Opening the gate...',
  'Calibrating the matrix...',
  'Dropping into the grid...',
];

class CallJoiningView extends StatefulWidget {
  const CallJoiningView({required this.displayName, this.phase, super.key});

  final String displayName;
  final JoinPhase? phase;

  @override
  State<CallJoiningView> createState() => _CallJoiningViewState();
}

class _CallJoiningViewState extends State<CallJoiningView> {
  static final _rng = Random();

  late String _label = _labelFor(widget.phase);

  String _labelFor(JoinPhase? phase) => switch (phase) {
        JoinPhase.authenticating =>
          _authenticatingPhrases[_rng.nextInt(_authenticatingPhrases.length)],
        JoinPhase.connectingMedia =>
          _connectingMediaPhrases[_rng.nextInt(_connectingMediaPhrases.length)],
        null => 'Joining call...',
      };

  @override
  void didUpdateWidget(covariant CallJoiningView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _label = _labelFor(widget.phase);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsingAvatar(displayName: widget.displayName),
          const SizedBox(height: 24),
          Text(widget.displayName, style: tt.titleMedium),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _label,
              key: ValueKey(_label),
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class CallReconnectingView extends StatelessWidget {
  const CallReconnectingView({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 48, color: cs.error),
          const SizedBox(height: 16),
          Text('Reconnecting...', style: tt.titleMedium),
        ],
      ),
    );
  }
}

class CallRingingOutgoingView extends StatefulWidget {
  const CallRingingOutgoingView({required this.displayName, required this.onCancel, super.key});

  final String displayName;
  final VoidCallback onCancel;

  @override
  State<CallRingingOutgoingView> createState() => _CallRingingOutgoingViewState();
}

class _CallRingingOutgoingViewState extends State<CallRingingOutgoingView> {
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final elapsed = formatCallElapsed(Duration(seconds: _elapsedSeconds));

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsingAvatar(displayName: widget.displayName),
          const SizedBox(height: 24),
          Text('Calling ${widget.displayName}...', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text(elapsed, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 32),
          FloatingActionButton(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
            onPressed: widget.onCancel,
            child: const Icon(Icons.call_end_rounded),
          ),
        ],
      ),
    );
  }
}

class CallEndedView extends StatelessWidget {
  const CallEndedView({this.error, this.onReturn, super.key});

  final String? error;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_end, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('Call ended', style: tt.titleMedium),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: tt.bodyMedium?.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
          ],
          if (onReturn != null) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onReturn,
              child: const Text('Return'),
            ),
          ],
        ],
      ),
    );
  }
}
// coverage:ignore-end

import 'package:flutter/material.dart';

String formatCallElapsed(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

class CallJoiningView extends StatelessWidget {
  const CallJoiningView({required this.displayName, super.key});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('Connecting...', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text(displayName, style: tt.bodyMedium),
        ],
      ),
    );
  }
}

class CallReconnectingView extends StatelessWidget {
  const CallReconnectingView({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 48),
          const SizedBox(height: 16),
          Text('Reconnecting...', style: tt.titleMedium),
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
          const Icon(Icons.call_end, size: 48),
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

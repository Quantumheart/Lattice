import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/features/calling/services/call_permission_service.dart';
import 'package:lattice/features/calling/widgets/call_controller.dart';
import 'package:lattice/features/calling/widgets/video_grid.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({required this.roomId, required this.displayName, super.key});

  final String roomId;
  final String displayName;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CallController(
      roomId: widget.roomId,
      displayName: widget.displayName,
    );
    _controller.addListener(_onControllerChanged);
    unawaited(_requestPermissionsAndJoin());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _requestPermissionsAndJoin() async {
    final granted = await CallPermissionService.request();
    if (!mounted) return;
    if (granted) {
      await _controller.join();
    } else {
      _controller.endWithError('Camera and microphone permissions are required');
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.state == CallState.ended) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
    setState(() {});
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: cs.primary,
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.displayName),
          actions: [
            IconButton(
              icon: const Icon(Icons.call_end),
              color: Colors.red,
              onPressed: _controller.hangUp,
            ),
          ],
        ),
        body: switch (_controller.state) {
          CallState.joining => _buildJoining(tt),
          CallState.connected => _buildConnected(tt),
          CallState.reconnecting => _buildReconnecting(tt),
          CallState.ended => _buildEnded(tt),
        },
      ),
    );
  }

  // ── State views ───────────────────────────────────────────────

  Widget _buildJoining(TextTheme tt) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('Connecting...', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text(widget.displayName, style: tt.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildConnected(TextTheme tt) {
    return Column(
      children: [
        Expanded(
          child: VideoGrid(participants: _controller.participants),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatElapsed(_controller.elapsed),
                style: tt.titleMedium,
              ),
              const SizedBox(height: 16),
              Text('Controls placeholder', style: tt.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReconnecting(TextTheme tt) {
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

  Widget _buildEnded(TextTheme tt) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.call_end, size: 48),
          const SizedBox(height: 16),
          Text('Call ended', style: tt.titleMedium),
          if (_controller.error != null) ...[
            const SizedBox(height: 8),
            Text(
              _controller.error!,
              style: tt.bodyMedium?.copyWith(color: Colors.red.shade300),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/models/incoming_call_info.dart';
import 'package:provider/provider.dart';

class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  StreamSubscription<IncomingCallInfo>? _sub;
  IncomingCallInfo? _incoming;
  CallService? _callService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final callService = context.read<CallService>();
    if (_callService != callService) {
      _callService?.removeListener(_onCallStateChanged);
      unawaited(_sub?.cancel());
      _callService = callService;
      _sub = callService.incomingCallStream.listen((info) {
        if (mounted) setState(() => _incoming = info);
      });
      callService.addListener(_onCallStateChanged);
    }
  }

  void _onCallStateChanged() {
    final callService = _callService;
    if (callService == null) return;
    if (callService.callState != LatticeCallState.ringingIncoming &&
        _incoming != null) {
      setState(() => _incoming = null);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _callService?.removeListener(_onCallStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_incoming != null)
          _IncomingCallDialog(
            info: _incoming!,
            onAcceptAudio: () => _accept(withVideo: false),
            onAcceptVideo: () => _accept(withVideo: true),
            onDecline: _decline,
          ),
      ],
    );
  }

  void _accept({required bool withVideo}) {
    _callService?.acceptCall(withVideo: withVideo);
    setState(() => _incoming = null);
  }

  void _decline() {
    _callService?.declineCall();
    setState(() => _incoming = null);
  }
}

class _IncomingCallDialog extends StatefulWidget {
  const _IncomingCallDialog({
    required this.info,
    required this.onAcceptAudio,
    required this.onAcceptVideo,
    required this.onDecline,
  });

  final IncomingCallInfo info;
  final VoidCallback onAcceptAudio;
  final VoidCallback onAcceptVideo;
  final VoidCallback onDecline;

  @override
  State<_IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<_IncomingCallDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    unawaited(_pulseCtrl.repeat(reverse: true));
    _pulseAnim = Tween<double>(begin: 1, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Positioned.fill(
      child: Material(
        color: cs.scrim.withValues(alpha: 0.6),
        child: Center(
          child: Card(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: CircleAvatar(
                      radius: 48,
                      child: Text(
                        widget.info.callerName.isNotEmpty
                            ? widget.info.callerName[0].toUpperCase()
                            : '?',
                        style: tt.headlineLarge,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(widget.info.callerName, style: tt.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    widget.info.isVideo ? 'Incoming video call' : 'Incoming voice call',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        heroTag: 'decline',
                        backgroundColor: cs.error,
                        onPressed: widget.onDecline,
                        child: const Icon(Icons.call_end_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        heroTag: 'accept_audio',
                        backgroundColor: Colors.green,
                        onPressed: widget.onAcceptAudio,
                        child: const Icon(Icons.call_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        heroTag: 'accept_video',
                        backgroundColor: Colors.green,
                        onPressed: widget.onAcceptVideo,
                        child: const Icon(Icons.videocam_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

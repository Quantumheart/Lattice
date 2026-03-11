import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/models/incoming_call_info.dart';
import 'package:lattice/shared/widgets/pulsing_avatar.dart';
import 'package:provider/provider.dart';

class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({required this.child, required this.router, super.key});

  final Widget child;
  final GoRouter router;

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  StreamSubscription<IncomingCallInfo>? _sub;
  StreamSubscription<String>? _nativeAcceptSub;
  IncomingCallInfo? _incoming;
  CallService? _callService;

  bool get _isDesktop => kIsWeb || (!Platform.isAndroid && !Platform.isIOS);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final callService = context.read<CallService>();
    if (_callService != callService) {
      _callService?.removeListener(_onCallStateChanged);
      unawaited(_sub?.cancel());
      unawaited(_nativeAcceptSub?.cancel());
      _callService = callService;
      _sub = callService.incomingCallStream.listen((info) {
        if (mounted && _isDesktop) setState(() => _incoming = info);
      });
      _nativeAcceptSub = callService.nativeAcceptedCallStream.listen((roomId) {
        if (mounted) {
          widget.router.goNamed(
            Routes.call,
            pathParameters: {'roomId': roomId},
          );
        }
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
    unawaited(_nativeAcceptSub?.cancel());
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
    final roomId = _incoming?.roomId;
    unawaited(_callService?.acceptCall(withVideo: withVideo));
    setState(() => _incoming = null);
    if (roomId != null) {
      widget.router.goNamed(
        Routes.call,
        pathParameters: {'roomId': roomId},
      );
    }
  }

  void _decline() {
    _callService?.declineCall();
    setState(() => _incoming = null);
  }
}

class _IncomingCallDialog extends StatelessWidget {
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
                  PulsingAvatar(
                    displayName: info.callerName,
                    endScale: 1.15,
                  ),
                  const SizedBox(height: 24),
                  Text(info.callerName, style: tt.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    info.isVideo ? 'Incoming video call' : 'Incoming voice call',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        heroTag: 'decline',
                        backgroundColor: cs.error,
                        foregroundColor: cs.onError,
                        onPressed: onDecline,
                        child: const Icon(Icons.call_end_rounded),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        heroTag: 'accept_audio',
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                        onPressed: onAcceptAudio,
                        child: const Icon(Icons.call_rounded),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        heroTag: 'accept_video',
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                        onPressed: onAcceptVideo,
                        child: const Icon(Icons.videocam_rounded),
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

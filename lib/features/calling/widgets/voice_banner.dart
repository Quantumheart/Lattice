import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/calling/widgets/call_state_views.dart'
    show formatCallElapsed;
import 'package:provider/provider.dart';

class VoiceBanner extends StatefulWidget {
  const VoiceBanner({required this.currentViewingRoomId, super.key});

  final String? currentViewingRoomId;

  @override
  State<VoiceBanner> createState() => _VoiceBannerState();
}

class _VoiceBannerState extends State<VoiceBanner> {
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final isConnected = callService.callState == LatticeCallState.connected;
    final activeRoomId = callService.activeCallRoomId;
    final viewingDifferentRoom =
        activeRoomId != null && activeRoomId != widget.currentViewingRoomId;

    if (!isConnected || !viewingDifferentRoom) return const SizedBox.shrink();

    final room = callService.client.getRoomById(activeRoomId);
    final roomName = room?.getLocalizedDisplayname() ?? 'Unknown room';
    final elapsed = callService.callElapsed;
    final elapsedText = elapsed != null ? formatCallElapsed(elapsed) : '';
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.headset_mic_rounded, size: 16, color: cs.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$roomName \u2014 $elapsedText',
                style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () => CallNavigator.endCall(context),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_dialog.dart';
import 'package:matrix/encryption.dart';
import 'package:provider/provider.dart';

class VerificationRequestListener extends StatefulWidget {
  const VerificationRequestListener({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  State<VerificationRequestListener> createState() =>
      _VerificationRequestListenerState();
}

class _VerificationRequestListenerState
    extends State<VerificationRequestListener> {
  StreamSubscription<KeyVerification>? _sub;
  MatrixService? _matrix;
  bool _dialogOpen = false;
  final Queue<KeyVerification> _pending = Queue<KeyVerification>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final matrix = context.read<MatrixService>();
    if (_matrix != matrix) {
      _matrix = matrix;
      _subscribe(matrix);
    }
  }

  void _subscribe(MatrixService matrix) {
    unawaited(_sub?.cancel());
    _sub = matrix.client.onKeyVerificationRequest.stream.listen(_onRequest);
  }

  void _onRequest(KeyVerification verification) {
    if (!mounted) return;
    if (verification.state == KeyVerificationState.done ||
        verification.state == KeyVerificationState.error) {
      return;
    }

    if (_dialogOpen) {
      debugPrint('[Kohera] Queuing verification request from '
          '${verification.userId} (dialog already open)');
      _pending.add(verification);
      return;
    }

    unawaited(_showVerification(verification));
  }

  Future<void> _showVerification(KeyVerification verification) async {
    debugPrint('[Kohera] Incoming verification request from '
        '${verification.userId}');

    final navContext =
        widget.router.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) return;

    _dialogOpen = true;
    final confirmed = await KeyVerificationDialog.show(
      navContext,
      verification: verification,
    );
    _dialogOpen = false;

    final matrix = _matrix;
    final isSelfVerification =
        matrix != null && verification.userId == matrix.client.userID;
    if (confirmed == true && isSelfVerification) {
      try {
        await matrix.chatBackup.runKeyRecovery();
      } catch (e) {
        debugPrint('[Kohera] Post-verification key recovery failed: $e');
      }
    }

    _showNextPending();
  }

  void _showNextPending() {
    if (!mounted) return;
    while (_pending.isNotEmpty) {
      final next = _pending.removeFirst();
      if (next.state != KeyVerificationState.done &&
          next.state != KeyVerificationState.error) {
        unawaited(_showVerification(next));
        return;
      }
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

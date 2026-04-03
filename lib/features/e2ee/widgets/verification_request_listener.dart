import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/e2ee/widgets/key_verification_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class VerificationRequestListener extends StatefulWidget {
  const VerificationRequestListener({required this.child, super.key});

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
    if (_dialogOpen) return;
    if (verification.state == KeyVerificationState.done ||
        verification.state == KeyVerificationState.error) {
      return;
    }

    debugPrint('[Lattice] Incoming verification request from '
        '${verification.userId}');

    _dialogOpen = true;
    KeyVerificationDialog.show(context, verification: verification).then((_) {
      _dialogOpen = false;
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

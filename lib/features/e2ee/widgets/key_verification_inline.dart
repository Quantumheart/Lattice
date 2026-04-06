import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/features/e2ee/widgets/key_verification_content.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

class KeyVerificationInline extends StatefulWidget {
  const KeyVerificationInline({
    required this.verification,
    required this.onDone,
    required this.onCancel,
    super.key,
  });

  final KeyVerification verification;
  final ValueChanged<bool> onDone;
  final VoidCallback onCancel;

  @override
  State<KeyVerificationInline> createState() => _KeyVerificationInlineState();
}

class _KeyVerificationInlineState extends State<KeyVerificationInline> {
  KeyVerificationState _state = KeyVerificationState.waitingAccept;

  @override
  void initState() {
    super.initState();
    widget.verification.onUpdate = _onUpdate;
    _state = widget.verification.state;
    if (_state == KeyVerificationState.askChoice) {
      unawaited(_autoSelectSas());
    }
  }

  void _onUpdate() {
    if (!mounted) return;
    final newState = widget.verification.state;

    if (newState == KeyVerificationState.askChoice) {
      unawaited(_autoSelectSas());
    }

    setState(() => _state = newState);
  }

  Future<void> _autoSelectSas() async {
    final methods = widget.verification.possibleMethods;
    if (methods.contains(EventTypes.Sas)) {
      debugPrint('[Verification] Auto-selecting SAS verification');
      await widget.verification.continueVerification(EventTypes.Sas);
    }
  }

  @override
  void dispose() {
    widget.verification.onUpdate = null;
    super.dispose();
  }

  void _handleCancel() {
    unawaited(widget.verification.cancel());
    widget.onCancel();
  }

  void _handleDone() {
    widget.onDone(_state == KeyVerificationState.done);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyVerificationContent(
          state: _state,
          verification: widget.verification,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: buildVerificationActions(
            state: _state,
            verification: widget.verification,
            onCancel: _handleCancel,
            onDone: _handleDone,
          ).map((w) => Padding(
            padding: const EdgeInsets.only(left: 8),
            child: w,
          ),).toList(),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_content.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

class KeyVerificationDialog extends StatefulWidget {
  final KeyVerification verification;

  const KeyVerificationDialog({
    required this.verification, super.key,
  });

  static Future<bool?> show(
    BuildContext context, {
    required KeyVerification verification,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => KeyVerificationDialog(verification: verification),
    );
  }

  @override
  State<KeyVerificationDialog> createState() => _KeyVerificationDialogState();
}

class _KeyVerificationDialogState extends State<KeyVerificationDialog> {
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

  void _cancel() {
    unawaited(widget.verification.cancel());
    Navigator.pop(context, false);
  }

  void _done() {
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final content = KeyVerificationContent(
      state: _state,
      verification: widget.verification,
    );

    return AlertDialog(
      title: Text(content.title),
      content: SizedBox(
        width: 400,
        child: content,
      ),
      actions: buildVerificationActions(
        state: _state,
        verification: widget.verification,
        onCancel: _cancel,
        onDone: _done,
      ),
    );
  }
}

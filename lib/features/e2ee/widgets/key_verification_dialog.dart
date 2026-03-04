import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

class KeyVerificationDialog extends StatefulWidget {
  final KeyVerification verification;

  const KeyVerificationDialog({
    super.key,
    required this.verification,
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
      _autoSelectSas();
    }
  }

  void _onUpdate() {
    if (!mounted) return;
    final newState = widget.verification.state;

    // Auto-select SAS when the SDK asks the user to choose a method.
    // QR verification is not yet supported, so skip the choice screen.
    if (newState == KeyVerificationState.askChoice) {
      _autoSelectSas();
    }

    setState(() {
      _state = newState;
    });
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 400,
        child: _buildContent(),
      ),
      actions: _buildActions(),
    );
  }

  String get _title {
    switch (_state) {
      case KeyVerificationState.askChoice:
      case KeyVerificationState.waitingAccept:
        return 'Verify device';
      case KeyVerificationState.askAccept:
        return 'Incoming verification';
      case KeyVerificationState.askSas:
        return 'Compare emoji';
      case KeyVerificationState.askSSSS:
        return 'Unlocking secrets';
      case KeyVerificationState.waitingSas:
        return 'Waiting...';
      case KeyVerificationState.showQRSuccess:
      case KeyVerificationState.confirmQRScan:
        return 'QR verification';
      case KeyVerificationState.done:
        return 'Verified';
      case KeyVerificationState.error:
        return 'Verification failed';
    }
  }

  Widget _buildContent() {
    switch (_state) {
      case KeyVerificationState.waitingAccept:
        return _buildWaiting('Waiting for the other device to accept...');

      case KeyVerificationState.askAccept:
        return const Text(
          'Another device is requesting verification. Accept to continue.',
        );

      case KeyVerificationState.askChoice:
        return _buildWaiting('Starting verification...');

      case KeyVerificationState.askSas:
        return _buildSasEmoji();

      case KeyVerificationState.askSSSS:
        return _buildWaiting('Unlocking encryption secrets...');

      case KeyVerificationState.waitingSas:
        return _buildWaiting('Verifying...');

      case KeyVerificationState.showQRSuccess:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary, size: 64),
            const SizedBox(height: 16),
            const Text('QR code scanned successfully.'),
          ],
        );

      case KeyVerificationState.confirmQRScan:
        return const Text(
          'Does the other device show a green checkmark?',
        );

      case KeyVerificationState.done:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified,
                color: Theme.of(context).colorScheme.primary, size: 64),
            const SizedBox(height: 16),
            const Text('Device verified successfully!'),
          ],
        );

      case KeyVerificationState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 64),
            const SizedBox(height: 16),
            Text(
              widget.verification.canceledReason ??
                  'Verification was cancelled or failed.',
              textAlign: TextAlign.center,
            ),
          ],
        );
    }
  }

  Widget _buildWaiting(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(message),
      ],
    );
  }

  Widget _buildSasEmoji() {
    final emojis = widget.verification.sasEmojis;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Verify that the following emoji appear on both devices, in the same order:',
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: emojis
              .map((e) => Semantics(
                    label: e.name,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Text(e.emoji,
                              style: const TextStyle(fontSize: 32)),
                        ),
                        const SizedBox(height: 4),
                        Text(e.name,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    switch (_state) {
      case KeyVerificationState.waitingAccept:
      case KeyVerificationState.askChoice:
      case KeyVerificationState.askSSSS:
      case KeyVerificationState.waitingSas:
        return [
          TextButton(
            onPressed: () {
              widget.verification.cancel();
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
        ];

      case KeyVerificationState.askAccept:
        return [
          TextButton(
            onPressed: () {
              widget.verification.cancel();
              Navigator.pop(context, false);
            },
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => widget.verification.acceptVerification(),
            child: const Text('Accept'),
          ),
        ];

      case KeyVerificationState.askSas:
        return [
          TextButton(
            onPressed: () => widget.verification.rejectSas(),
            child: const Text('They don\'t match'),
          ),
          FilledButton(
            onPressed: () => widget.verification.acceptSas(),
            child: const Text('They match'),
          ),
        ];

      case KeyVerificationState.confirmQRScan:
        return [
          TextButton(
            onPressed: () {
              widget.verification.cancel();
              Navigator.pop(context, false);
            },
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () =>
                widget.verification.acceptQRScanConfirmation(),
            child: const Text('Yes'),
          ),
        ];

      case KeyVerificationState.showQRSuccess:
        return [
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Done'),
          ),
        ];

      case KeyVerificationState.done:
        return [
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Done'),
          ),
        ];

      case KeyVerificationState.error:
        return [
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ];
    }
  }
}

import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';

// ── Key verification content ────────────────────────────────────

class KeyVerificationContent extends StatelessWidget {
  const KeyVerificationContent({
    required this.state,
    required this.verification,
    super.key,
  });

  final KeyVerificationState state;
  final KeyVerification verification;

  String get title {
    switch (state) {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildContent(context),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (state) {
      case KeyVerificationState.waitingAccept:
        return _buildWaiting('Waiting for the other device to accept...');

      case KeyVerificationState.askAccept:
        return const Text(
          'Another device is requesting verification. Accept to continue.',
        );

      case KeyVerificationState.askChoice:
        return _buildWaiting('Starting verification...');

      case KeyVerificationState.askSas:
        return _buildSasEmoji(context);

      case KeyVerificationState.askSSSS:
        return _buildWaiting('Unlocking encryption secrets...');

      case KeyVerificationState.waitingSas:
        return _buildWaiting('Verifying...');

      case KeyVerificationState.showQRSuccess:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary, size: 64,),
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
                color: Theme.of(context).colorScheme.primary, size: 64,),
            const SizedBox(height: 16),
            const Text('Device verified successfully!'),
          ],
        );

      case KeyVerificationState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 64,),
            const SizedBox(height: 16),
            Text(
              verification.canceledReason ??
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

  Widget _buildSasEmoji(BuildContext context) {
    final emojis = verification.sasEmojis;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Verify that the following emoji appear on both devices, '
          'in the same order:',
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
                              style: const TextStyle(fontSize: 32),),
                        ),
                        const SizedBox(height: 4),
                        Text(e.name,
                            style: Theme.of(context).textTheme.bodySmall,),
                      ],
                    ),
                  ),)
              .toList(),
        ),
      ],
    );
  }
}

// ── Action buttons builder ──────────────────────────────────────

List<Widget> buildVerificationActions({
  required KeyVerificationState state,
  required KeyVerification verification,
  required VoidCallback onCancel,
  required VoidCallback onDone,
}) {
  switch (state) {
    case KeyVerificationState.waitingAccept:
    case KeyVerificationState.askChoice:
    case KeyVerificationState.askSSSS:
    case KeyVerificationState.waitingSas:
      return [
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ];

    case KeyVerificationState.askAccept:
      return [
        TextButton(onPressed: onCancel, child: const Text('Reject')),
        FilledButton(
          onPressed: () => verification.acceptVerification(),
          child: const Text('Accept'),
        ),
      ];

    case KeyVerificationState.askSas:
      return [
        TextButton(
          onPressed: () => verification.rejectSas(),
          child: const Text("They don't match"),
        ),
        FilledButton(
          onPressed: () => verification.acceptSas(),
          child: const Text('They match'),
        ),
      ];

    case KeyVerificationState.confirmQRScan:
      return [
        TextButton(onPressed: onCancel, child: const Text('No')),
        FilledButton(
          onPressed: () => verification.acceptQRScanConfirmation(),
          child: const Text('Yes'),
        ),
      ];

    case KeyVerificationState.showQRSuccess:
    case KeyVerificationState.done:
      return [
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ];

    case KeyVerificationState.error:
      return [
        FilledButton(onPressed: onCancel, child: const Text('Close')),
      ];
  }
}

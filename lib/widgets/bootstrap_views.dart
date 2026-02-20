import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption.dart';

import 'bootstrap_controller.dart';

/// Builds the main content area for the bootstrap dialog.
Widget buildBootstrapContent({
  required BuildContext context,
  required BootstrapController controller,
  required TextEditingController recoveryKeyController,
}) {
  switch (controller.state) {
    case BootstrapState.loading:
    case BootstrapState.askWipeSsss:
    case BootstrapState.askWipeCrossSigning:
    case BootstrapState.askWipeOnlineKeyBackup:
    case BootstrapState.askBadSsss:
      return _buildLoading('Preparing...');

    case BootstrapState.askSetupCrossSigning:
      return _buildLoading('Setting up cross-signing...');

    case BootstrapState.askSetupOnlineKeyBackup:
      return _buildLoading('Setting up key backup...');

    case BootstrapState.askNewSsss:
      return _buildNewSsss(context, controller);

    case BootstrapState.openExistingSsss:
      return _buildOpenExistingSsss(context, controller, recoveryKeyController);

    case BootstrapState.askUseExistingSsss:
    case BootstrapState.askUnlockSsss:
      return _buildLoading('Preparing...');

    case BootstrapState.done:
      return _buildDone(context);

    case BootstrapState.error:
      return _buildError(context, controller);
  }
}

/// Builds the action buttons for the bootstrap dialog.
List<Widget> buildBootstrapActions({
  required BuildContext context,
  required BootstrapController controller,
  required TextEditingController recoveryKeyController,
}) {
  switch (controller.state) {
    case BootstrapState.loading:
    case BootstrapState.askWipeSsss:
    case BootstrapState.askWipeCrossSigning:
    case BootstrapState.askSetupCrossSigning:
    case BootstrapState.askWipeOnlineKeyBackup:
    case BootstrapState.askSetupOnlineKeyBackup:
    case BootstrapState.askBadSsss:
    case BootstrapState.askUseExistingSsss:
    case BootstrapState.askUnlockSsss:
      return [
        TextButton(
          onPressed: controller.requestCancel,
          child: const Text('Cancel'),
        ),
      ];

    case BootstrapState.askNewSsss:
      final canProceed =
          !controller.generatingKey && controller.canConfirmNewKey;
      return [
        TextButton(
          onPressed: controller.requestCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canProceed ? controller.confirmNewSsss : null,
          child: const Text('Next'),
        ),
      ];

    case BootstrapState.openExistingSsss:
      return [
        TextButton(
          onPressed: controller.requestCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => controller
              .unlockExistingSsss(recoveryKeyController.text.trim()),
          child: const Text('Unlock'),
        ),
      ];

    case BootstrapState.done:
      return [
        FilledButton(
          onPressed: controller.onDone,
          child: const Text('Done'),
        ),
      ];

    case BootstrapState.error:
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: controller.retry,
          child: const Text('Retry'),
        ),
      ];
  }
}

// ── Private view helpers ──────────────────────────────────────────

Widget _buildLoading(String message) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 16),
      Text(message),
    ],
  );
}

Widget _buildNewSsss(BuildContext context, BootstrapController controller) {
  if (controller.generatingKey) {
    return _buildLoading('Generating recovery key...');
  }
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Store this key somewhere safe. You will need it to '
        'recover your encrypted messages on a new device.',
      ),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          controller.newRecoveryKey ?? '',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: controller.keyCopied
              ? null
              : () {
                  if (controller.newRecoveryKey != null) {
                    Clipboard.setData(
                        ClipboardData(text: controller.newRecoveryKey!));
                    controller.setKeyCopied();
                  }
                },
          icon: Icon(
            controller.keyCopied ? Icons.check : Icons.copy,
            size: 18,
          ),
          label: Text(controller.keyCopied ? 'Copied' : 'Copy'),
        ),
      ),
      CheckboxListTile(
        value: controller.saveToDevice,
        onChanged: (v) => controller.setSaveToDevice(v ?? false),
        title: const Text('Save to device'),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        mouseCursor: SystemMouseCursors.click,
      ),
    ],
  );
}

Widget _buildOpenExistingSsss(
  BuildContext context,
  BootstrapController controller,
  TextEditingController recoveryKeyController,
) {
  if (controller.verifying) {
    return _buildLoading('Verifying with another device...');
  }
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Enter your recovery key to unlock your existing backup.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: recoveryKeyController,
        decoration: InputDecoration(
          labelText: 'Recovery key',
          errorText: controller.recoveryKeyError,
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        value: controller.saveToDevice,
        onChanged: (v) => controller.setSaveToDevice(v ?? false),
        title: const Text('Save to device'),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        mouseCursor: SystemMouseCursors.click,
      ),
      const SizedBox(height: 4),
      const Divider(),
      const SizedBox(height: 4),
      Center(
        child: OutlinedButton.icon(
          onPressed: controller.requestVerification,
          icon: const Icon(Icons.devices, size: 18),
          label: const Text('Verify with another device'),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: controller.requestLostKeyConfirmation,
        child: const Text('I lost my recovery key'),
      ),
    ],
  );
}

Widget _buildDone(BuildContext context) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.check_circle,
        color: Theme.of(context).colorScheme.primary,
        size: 64,
      ),
      const SizedBox(height: 16),
      const Text('Your chat backup has been set up successfully.'),
    ],
  );
}

Widget _buildError(BuildContext context, BootstrapController controller) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
        size: 64,
      ),
      const SizedBox(height: 16),
      Text(
        controller.error ?? 'An unexpected error occurred during backup setup.',
        textAlign: TextAlign.center,
      ),
    ],
  );
}

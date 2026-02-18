import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption.dart';
import 'package:provider/provider.dart';

import 'dart:async';

import '../services/matrix_service.dart';
import 'bootstrap_controller.dart';
import 'bootstrap_views.dart';
import 'key_verification_dialog.dart';

class BootstrapDialog extends StatefulWidget {
  final MatrixService matrixService;
  final bool wipeExisting;

  const BootstrapDialog({
    super.key,
    required this.matrixService,
    this.wipeExisting = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    bool wipeExisting = false,
  }) {
    final matrixService = context.read<MatrixService>();
    return showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BootstrapDialog(
        matrixService: matrixService,
        wipeExisting: wipeExisting,
      ),
    );
  }

  @override
  State<BootstrapDialog> createState() => _BootstrapDialogState();
}

class _BootstrapDialogState extends State<BootstrapDialog> {
  late final BootstrapController _controller;
  final _recoveryKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = BootstrapController(
      matrixService: widget.matrixService,
      wipeExisting: widget.wipeExisting,
    );
    _controller.addListener(_onControllerChanged);
    _controller.startBootstrap();
  }

  @override
  void dispose() {
    Clipboard.setData(const ClipboardData(text: ''));
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _recoveryKeyController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Handle deferred advance (replaces addPostFrameCallback in old code).
    final advance = _controller.deferredAdvance;
    if (advance != null) {
      _controller.deferredAdvance = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => advance());
    }

    // Handle stored recovery key from controller.
    final storedKey = _controller.consumeStoredRecoveryKey();
    if (storedKey != null) {
      _recoveryKeyController.text = storedKey;
    }

    // Handle pending UI actions.
    final action = _controller.pendingAction;
    if (action != BootstrapAction.none) {
      _controller.clearPendingAction();
      switch (action) {
        case BootstrapAction.startVerification:
          _showVerificationDialog();
          break;
        case BootstrapAction.confirmLostKey:
          _showLostKeyConfirmation();
          break;
        case BootstrapAction.done:
          Clipboard.setData(const ClipboardData(text: ''));
          Navigator.pop(context, true);
          break;
        case BootstrapAction.none:
          break;
      }
    }

    setState(() {});
  }

  Future<void> _showVerificationDialog() async {
    final client = widget.matrixService.client;
    final encryption = client.encryption;
    if (encryption == null) return;

    _controller.setVerifying(true);

    try {
      await client.updateUserDeviceKeys();

      final sub =
          encryption.ssss.onSecretStored.stream.listen((_) async {
        _controller.cancelSecretStoredSub();
        if (mounted) {
          _controller.setVerifying(false);
          final bootstrap = _controller.bootstrap;
          final ssssKey = bootstrap?.newSsssKey;
          if (ssssKey != null && ssssKey.isUnlocked) {
            await bootstrap!.openExistingSsss();
          }
        }
      });
      _controller.onSecretStoredSub(sub);

      final verification = KeyVerification(
        encryption: encryption,
        userId: client.userID!,
      );
      verification.start();

      if (!mounted) return;

      final result = await KeyVerificationDialog.show(
        context,
        verification: verification,
      );

      if (result != true) {
        _controller.cancelSecretStoredSub();
        if (mounted) {
          _controller.setVerifying(false);
        }
      }
    } catch (e) {
      _controller.cancelSecretStoredSub();
      if (mounted) {
        _controller.setVerifying(false);
      }
    }
  }

  void _showLostKeyConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lost recovery key?'),
        content: const Text(
          'If you lost your recovery key, you will need to create a new '
          'backup. Your existing encrypted message history may be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _recoveryKeyController.clear();
              _controller.restartWithWipe();
            },
            child: const Text('Create new backup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_controller.title),
      content: SizedBox(
        width: 400,
        child: buildBootstrapContent(
          context: context,
          controller: _controller,
          recoveryKeyController: _recoveryKeyController,
        ),
      ),
      actions: buildBootstrapActions(
        context: context,
        controller: _controller,
        recoveryKeyController: _recoveryKeyController,
      ),
    );
  }
}

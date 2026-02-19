import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

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
  StreamSubscription? _uiaSub;

  @override
  void initState() {
    super.initState();
    _controller = BootstrapController(
      matrixService: widget.matrixService,
      wipeExisting: widget.wipeExisting,
    );
    _controller.addListener(_onControllerChanged);
    _uiaSub = widget.matrixService.onUiaRequest.listen(_showUiaPasswordPrompt);
    _controller.startBootstrap();
  }

  @override
  void dispose() {
    Clipboard.setData(const ClipboardData(text: ''));
    _uiaSub?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _recoveryKeyController.dispose();
    super.dispose();
  }

  Future<void> _showUiaPasswordPrompt(UiaRequest request) async {
    if (!mounted) return;
    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Authentication required'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, passwordController.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    passwordController.dispose();
    if (password != null && password.isNotEmpty) {
      widget.matrixService.completeUiaWithPassword(request, password);
    } else {
      request.cancel();
    }
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

    // Handle pending UI actions — deferred to avoid Navigator operations
    // during the notification/build phase.
    final action = _controller.pendingAction;
    if (action != BootstrapAction.none) {
      _controller.clearPendingAction();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (action) {
          case BootstrapAction.startVerification:
            _showVerificationDialog();
            break;
          case BootstrapAction.confirmLostKey:
            _showLostKeyConfirmation();
            break;
          case BootstrapAction.confirmCancel:
            _showCancelConfirmation();
            break;
          case BootstrapAction.done:
            Clipboard.setData(const ClipboardData(text: ''));
            Navigator.pop(context, true);
            break;
          case BootstrapAction.none:
            break;
        }
      });
    }

    if (mounted) setState(() {});
  }

  Future<void> _showVerificationDialog() async {
    final client = widget.matrixService.client;
    final encryption = client.encryption;
    if (encryption == null) return;

    _controller.setVerifying(true);

    try {
      await client.updateUserDeviceKeys();

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
        if (mounted) _controller.setVerifying(false);
        return;
      }

      // After successful verification, wait for secrets to propagate
      // (matching FluffyChat's approach).
      if (!mounted) return;

      final allCached = await encryption.keyManager.isCached() &&
          await encryption.crossSigning.isCached();
      if (!allCached) {
        // Wait for secrets to arrive via sync.
        final sub = encryption.ssss.onSecretStored.stream.listen((_) {});
        _controller.onSecretStoredSub(sub);
        await encryption.ssss.onSecretStored.stream.first;
        _controller.cancelSecretStoredSub();
      }

      if (!mounted) return;

      // Secrets are cached — finalize the bootstrap.
      _controller.setVerifying(false);
      await _controller.onDone();
    } catch (e) {
      _controller.cancelSecretStoredSub();
      if (mounted) {
        _controller.setVerifying(false);
      }
    }
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip backup setup?'),
        content: const Text(
          'Without a chat backup, you may lose access to your '
          'encrypted messages if you lose this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue setup'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, false);
            },
            child: const Text('Skip'),
          ),
        ],
      ),
    );
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

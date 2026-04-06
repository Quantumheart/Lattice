import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/e2ee/widgets/bootstrap_controller.dart';
import 'package:lattice/features/e2ee/widgets/key_verification_inline.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

// ── Step enum ───────────────────────────────────────────────────

enum _SetupStep {
  explainer,
  skipConfirm,
  loading,
  savingKey,
  unlock,
  createNewKey,
  deviceVerification,
  done,
  management,
  disableConfirm,
  error,
}

class E2eeSetupScreen extends StatefulWidget {
  const E2eeSetupScreen({super.key});

  @override
  State<E2eeSetupScreen> createState() => _E2eeSetupScreenState();
}

class _E2eeSetupScreenState extends State<E2eeSetupScreen> {
  late MatrixService _matrixService;
  BootstrapController? _controller;
  final _recoveryKeyController = TextEditingController();
  StreamSubscription<UiaRequest<dynamic>>? _uiaSub;
  bool _uiaPromptShowing = false;
  _SetupStep _step = _SetupStep.explainer;
  KeyVerification? _activeVerification;

  @override
  void initState() {
    super.initState();
    _matrixService = context.read<MatrixService>();
    _uiaSub = _matrixService.onUiaRequest.listen(_showUiaPasswordPrompt);

    if (_matrixService.chatBackupEnabled) {
      _step = _SetupStep.management;
    }
  }

  @override
  void dispose() {
    _cleanupController();
    unawaited(_uiaSub?.cancel());
    _recoveryKeyController.dispose();
    _activeVerification?.onUpdate = null;
    super.dispose();
  }

  // ── Controller lifecycle ──────────────────────────────────────

  void _startBootstrap({bool wipeExisting = false}) {
    _cleanupController();
    _controller = BootstrapController(
      matrixService: _matrixService,
      wipeExisting: wipeExisting,
    );
    _controller!.addListener(_onControllerChanged);
    setState(() => _step = _SetupStep.loading);
    unawaited(_controller!.startBootstrap());
  }

  void _cleanupController() {
    if (_controller != null) {
      if (_controller!.keyCopied) {
        unawaited(Clipboard.setData(const ClipboardData(text: '')));
      }
      _controller!.removeListener(_onControllerChanged);
      _controller!.dispose();
      _controller = null;
    }
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;

    final advance = controller.deferredAdvance;
    if (advance != null) {
      controller.deferredAdvance = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => advance());
    }

    final storedKey = controller.consumeStoredRecoveryKey();
    if (storedKey != null) {
      _recoveryKeyController.text = storedKey;
    }

    final action = controller.pendingAction;
    if (action != BootstrapAction.none) {
      controller.clearPendingAction();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (action) {
          case BootstrapAction.startVerification:
            unawaited(_startVerification());
          case BootstrapAction.confirmLostKey:
            setState(() => _step = _SetupStep.createNewKey);
          case BootstrapAction.confirmCancel:
            setState(() => _step = _SetupStep.skipConfirm);
          case BootstrapAction.done:
            unawaited(_finishSetup());
          case BootstrapAction.none:
            break;
        }
      });
      return;
    }

    final state = controller.state;
    final newStep = switch (state) {
      BootstrapState.loading ||
      BootstrapState.askWipeSsss ||
      BootstrapState.askWipeCrossSigning ||
      BootstrapState.askSetupCrossSigning ||
      BootstrapState.askWipeOnlineKeyBackup ||
      BootstrapState.askSetupOnlineKeyBackup ||
      BootstrapState.askBadSsss ||
      BootstrapState.askUseExistingSsss ||
      BootstrapState.askUnlockSsss =>
        _SetupStep.loading,
      BootstrapState.askNewSsss => _SetupStep.savingKey,
      BootstrapState.openExistingSsss => _SetupStep.unlock,
      BootstrapState.done => _SetupStep.done,
      BootstrapState.error => _SetupStep.error,
    };

    if (_step == _SetupStep.deviceVerification ||
        _step == _SetupStep.createNewKey ||
        _step == _SetupStep.skipConfirm) {
      if (mounted) setState(() {});
      return;
    }

    if (mounted) setState(() => _step = newStep);
  }

  // ── Verification ──────────────────────────────────────────────

  Future<void> _startVerification() async {
    final client = _matrixService.client;
    final encryption = client.encryption;
    if (encryption == null) return;

    setState(() => _step = _SetupStep.deviceVerification);

    await client.updateUserDeviceKeys();

    final verification = KeyVerification(
      encryption: encryption,
      userId: client.userID!,
      deviceId: '*',
    );
    await verification.start();
    encryption.keyVerificationManager.addRequest(verification);

    if (!mounted) return;
    setState(() => _activeVerification = verification);
  }

  Future<void> _onVerificationDone(bool success) async {
    if (!success) {
      _activeVerification = null;
      setState(() => _step = _SetupStep.unlock);
      _controller?.setVerifying(false);
      return;
    }

    _controller?.setVerifying(true);

    final encryption = _matrixService.client.encryption;
    if (encryption != null) {
      for (var i = 0; i < 5; i++) {
        if (!mounted) return;
        final cached = await encryption.keyManager.isCached() &&
            await encryption.crossSigning.isCached();
        if (cached) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    if (!mounted) return;
    _activeVerification = null;
    _controller?.setVerifying(false);
    await _controller?.onDone();
  }

  void _onVerificationCancel() {
    _activeVerification = null;
    _controller?.setVerifying(false);
    setState(() => _step = _SetupStep.unlock);
  }

  // ── UIA prompt ────────────────────────────────────────────────

  Future<void> _showUiaPasswordPrompt(UiaRequest<dynamic> request) async {
    if (!mounted || _uiaPromptShowing) return;
    _uiaPromptShowing = true;
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
    _uiaPromptShowing = false;
    if (password != null && password.isNotEmpty) {
      _matrixService.completeUiaWithPassword(request, password);
    } else {
      request.cancel();
    }
  }

  // ── Finish / Skip ─────────────────────────────────────────────

  Future<void> _finishSetup() async {
    if (_controller?.keyCopied ?? false) {
      unawaited(Clipboard.setData(const ClipboardData(text: '')));
    }
    if (mounted) context.go('/');
  }

  void _skip() {
    _matrixService.skipSetup();
    context.go('/');
  }

  // ── Build ─────────────────────────────────────────────────────

  int get _currentDot => switch (_step) {
        _SetupStep.explainer || _SetupStep.skipConfirm => 0,
        _SetupStep.done => 2,
        _ => 1,
      };

  bool get _showDots =>
      _step != _SetupStep.management && _step != _SetupStep.disableConfirm;

  @override
  Widget build(BuildContext context) {
    final isBlocking = !_matrixService.hasSkippedSetup &&
        _matrixService.chatBackupNeeded == true;

    return PopScope(
      canPop: !isBlocking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isBlocking) {
          setState(() => _step = _SetupStep.skipConfirm);
        }
      },
      child: Scaffold(
        appBar: isBlocking
            ? null
            : AppBar(
                leading: BackButton(onPressed: () => context.go('/')),
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    if (_showDots) ...[
                      const SizedBox(height: 24),
                      _StepDots(current: _currentDot, total: 3),
                      const SizedBox(height: 32),
                    ] else
                      const SizedBox(height: 24),
                    Expanded(child: _buildContent()),
                    const SizedBox(height: 16),
                    _buildActions(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return switch (_step) {
      _SetupStep.explainer => _buildExplainer(),
      _SetupStep.skipConfirm => _buildSkipConfirm(),
      _SetupStep.loading => _buildLoading(),
      _SetupStep.savingKey => _buildSavingKey(),
      _SetupStep.unlock => _buildUnlock(),
      _SetupStep.createNewKey => _buildCreateNewKey(),
      _SetupStep.deviceVerification => _buildDeviceVerification(),
      _SetupStep.done => _buildDone(),
      _SetupStep.management => _buildManagement(),
      _SetupStep.disableConfirm => _buildDisableConfirm(),
      _SetupStep.error => _buildError(),
    };
  }

  Widget _buildActions() {
    final controller = _controller;
    return switch (_step) {
      _SetupStep.explainer => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = _SetupStep.skipConfirm),
              child: const Text('Skip for now'),
            ),
            FilledButton(
              onPressed: _startBootstrap,
              child: const Text('Next'),
            ),
          ],
        ),
      _SetupStep.skipConfirm => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = _SetupStep.explainer),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: _skip,
              child: const Text('Skip anyway'),
            ),
          ],
        ),
      _SetupStep.loading => const SizedBox.shrink(),
      _SetupStep.savingKey => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: controller?.requestCancel,
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: controller != null &&
                      !controller.generatingKey &&
                      controller.canConfirmNewKey
                  ? controller.confirmNewSsss
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      _SetupStep.unlock => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: controller?.requestCancel,
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => controller
                  ?.unlockExistingSsss(_recoveryKeyController.text.trim()),
              child: const Text('Unlock'),
            ),
          ],
        ),
      _SetupStep.createNewKey => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = _SetupStep.unlock),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () {
                _recoveryKeyController.clear();
                _controller?.restartWithWipe();
              },
              child: const Text('Create new backup'),
            ),
          ],
        ),
      _SetupStep.deviceVerification => const SizedBox.shrink(),
      _SetupStep.done => FilledButton(
          onPressed: _finishSetup,
          child: const Text('Done'),
        ),
      _SetupStep.management || _SetupStep.disableConfirm =>
        const SizedBox.shrink(),
      _SetupStep.error => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => _controller?.retry(),
              child: const Text('Retry'),
            ),
          ],
        ),
    };
  }

  // ── Content views ─────────────────────────────────────────────

  Widget _buildExplainer() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What is key backup?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your messages are encrypted end-to-end. A recovery key '
            'lets you access them on new devices or if you reinstall.',
          ),
          const SizedBox(height: 24),
          const Text('Without it:'),
          const SizedBox(height: 8),
          ..._bulletPoints([
            'Message history is lost',
            "Cross-device verification won't work",
            'Some features may not work',
          ]),
        ],
      ),
    );
  }

  Widget _buildSkipConfirm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Are you sure?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text('Without key backup:'),
          const SizedBox(height: 8),
          ..._bulletPoints([
            'Message history is lost',
            "Cross-device verification won't work",
            'Some features may not work',
          ]),
          const SizedBox(height: 16),
          const Text('You can set this up later in Settings > Chat backup.'),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    final controller = _controller;
    final message = switch (controller?.state) {
      BootstrapState.askSetupCrossSigning => 'Setting up cross-signing...',
      BootstrapState.askSetupOnlineKeyBackup => 'Setting up key backup...',
      _ => 'Preparing...',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }

  Widget _buildSavingKey() {
    final controller = _controller!;
    if (controller.generatingKey) {
      return _buildLoading();
    }

    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Save your recovery key',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'Store this key somewhere safe \u2014 a password manager, '
            'printed copy, or secure note.',
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
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
                        unawaited(Clipboard.setData(
                            ClipboardData(text: controller.newRecoveryKey!),),);
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
      ),
    );
  }

  Widget _buildUnlock() {
    final controller = _controller;
    if (controller != null && controller.verifying) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Verifying with another device...'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unlock your backup',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text('Enter your recovery key to restore your message history.'),
          const SizedBox(height: 16),
          TextField(
            controller: _recoveryKeyController,
            decoration: InputDecoration(
              labelText: 'Recovery key',
              errorText: controller?.recoveryKeyError,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: controller?.saveToDevice ?? false,
            onChanged: (v) => controller?.setSaveToDevice(v ?? false),
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
              onPressed: controller?.requestVerification,
              icon: const Icon(Icons.devices, size: 18),
              label: const Text('Verify with another device'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: controller?.requestLostKeyConfirmation,
            child: const Text('Create new key'),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateNewKey() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create new backup?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'This will create a new recovery key. If you had a previous '
            'backup, that encrypted message history may be lost.',
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceVerification() {
    if (_activeVerification == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Starting verification...'),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _onVerificationCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify with another device',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'Open Lattice on another device and confirm the emoji match.',
          ),
          const SizedBox(height: 24),
          KeyVerificationInline(
            verification: _activeVerification!,
            onDone: _onVerificationDone,
            onCancel: _onVerificationCancel,
          ),
        ],
      ),
    );
  }

  Widget _buildDone() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: cs.primary, size: 64),
          const SizedBox(height: 16),
          Text(
            "You're all set!",
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your messages are backed up and will be available '
            'across all your devices.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildManagement() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: cs.primary, size: 64),
          const SizedBox(height: 16),
          Text(
            'Chat backup',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your keys are backed up. Your encrypted messages are '
            'secure and accessible from any device.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () => _startBootstrap(wipeExisting: true),
            child: const Text('Create new key'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _step = _SetupStep.disableConfirm),
            child: Text(
              'Disable backup',
              style: TextStyle(color: cs.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisableConfirm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Disable backup?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your recovery key and server-side backup will be deleted. '
            'You will lose access to your encrypted message history on '
            'other devices.',
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => _step = _SetupStep.management),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () async {
                  await _matrixService.disableChatBackup();
                  if (mounted) context.go('/');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Disable backup'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 64),
          const SizedBox(height: 16),
          Text(
            _controller?.error ??
                'An unexpected error occurred during backup setup.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  List<Widget> _bulletPoints(List<String> items) {
    return items
        .map((item) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('\u2022  '),
                  Expanded(child: Text(item),),
                ],
              ),
            ),)
        .toList();
  }
}

// ── Step dot indicator ──────────────────────────────────────────

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final isActive = i <= current;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? cs.primary : cs.outlineVariant,
            ),
          ),
        );
      }),
    );
  }
}

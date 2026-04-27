import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/chat_backup_service.dart';
import 'package:kohera/features/e2ee/widgets/bootstrap_controller.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_inline.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

// ── Screen-local steps (outside bootstrap lifecycle) ───────────

enum _ScreenStep { explainer, skipConfirm, createNewKey, management, disableConfirm }

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
  _ScreenStep? _localStep = _ScreenStep.explainer;

  @override
  void initState() {
    super.initState();
    _matrixService = context.read<MatrixService>();
    _uiaSub = _matrixService.uia.onUiaRequest.listen(_showUiaPasswordPrompt);

    if (_matrixService.chatBackup.chatBackupEnabled) {
      _localStep = _ScreenStep.management;
    }
  }

  @override
  void dispose() {
    _cleanupController();
    unawaited(_uiaSub?.cancel());
    _recoveryKeyController.dispose();
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
    setState(() => _localStep = null);
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
    final storedKey = _controller?.consumeStoredRecoveryKey();
    if (storedKey != null) {
      _recoveryKeyController.text = storedKey;
    }
    if (mounted) setState(() {});
  }

  // ── UIA prompt ────────────────────────────────────────────────

  Future<void> _showUiaPasswordPrompt(UiaRequest<dynamic> request) async {
    if (!mounted || _uiaPromptShowing) return;
    _uiaPromptShowing = true;
    var passwordValue = '';
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Authentication required'),
        content: TextField(
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => passwordValue = value,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, passwordValue),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    _uiaPromptShowing = false;
    if (password != null && password.isNotEmpty) {
      _matrixService.uia.completeUiaWithPassword(request, password);
    } else {
      request.cancel();
    }
  }

  // ── Finish / Skip ─────────────────────────────────────────────

  Future<void> _finishSetup() async {
    final shouldClearClipboard = _controller?.keyCopied ?? false;
    _matrixService.skipSetup();
    if (mounted) context.go('/');
    if (shouldClearClipboard) {
      unawaited(Clipboard.setData(const ClipboardData(text: '')));
    }
  }

  void _skip() {
    _matrixService.skipSetup();
    context.go('/');
  }

  // ── Build ─────────────────────────────────────────────────────

  int get _currentDot {
    if (_localStep != null) {
      return _localStep == _ScreenStep.explainer ||
              _localStep == _ScreenStep.skipConfirm
          ? 0
          : 1;
    }
    return _controller?.phase == SetupPhase.done ? 2 : 1;
  }

  bool get _showDots =>
      _localStep != _ScreenStep.management &&
      _localStep != _ScreenStep.disableConfirm;

  @override
  Widget build(BuildContext context) {
    final backupNeeded = context.select<ChatBackupService, bool?>(
      (s) => s.chatBackupNeeded,
    );

    if (backupNeeded == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!backupNeeded && _localStep == _ScreenStep.explainer) {
      _localStep = _ScreenStep.management;
    }

    final isBlocking = !_matrixService.hasSkippedSetup && backupNeeded;

    return PopScope(
      canPop: !isBlocking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isBlocking) {
          setState(() => _localStep = _ScreenStep.skipConfirm);
        }
      },
      child: Scaffold(
        appBar: isBlocking
            ? null
            : AppBar(
                leading: BackButton(
                  onPressed: () {
                    if (_localStep != null) {
                      context.go('/');
                    } else {
                      setState(() => _localStep = _ScreenStep.skipConfirm);
                    }
                  },
                ),
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
    if (_localStep != null) {
      return switch (_localStep!) {
        _ScreenStep.explainer => _buildExplainer(),
        _ScreenStep.skipConfirm => _buildSkipConfirm(),
        _ScreenStep.createNewKey => _buildCreateNewKey(),
        _ScreenStep.management => _buildManagement(),
        _ScreenStep.disableConfirm => _buildDisableConfirm(),
      };
    }
    return switch (_controller!.phase) {
      SetupPhase.loading => _buildLoading(),
      SetupPhase.savingKey => _buildSavingKey(),
      SetupPhase.unlock => _buildUnlock(),
      SetupPhase.verification => _buildDeviceVerification(),
      SetupPhase.done => _buildDone(),
      SetupPhase.error => _buildError(),
    };
  }

  Widget _buildActions() {
    if (_localStep != null) {
      return switch (_localStep!) {
        _ScreenStep.explainer => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => _localStep = _ScreenStep.skipConfirm),
                child: const Text('Skip for now'),
              ),
              FilledButton(
                onPressed: _startBootstrap,
                child: const Text('Next'),
              ),
            ],
          ),
        _ScreenStep.skipConfirm => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => _localStep = _ScreenStep.explainer),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: _skip,
                child: const Text('Skip anyway'),
              ),
            ],
          ),
        _ScreenStep.createNewKey => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => setState(() => _localStep = null),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () {
                  _recoveryKeyController.clear();
                  _controller?.restartWithWipe();
                  setState(() => _localStep = null);
                },
                child: const Text('Create new backup'),
              ),
            ],
          ),
        _ScreenStep.management => const SizedBox.shrink(),
        _ScreenStep.disableConfirm => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => _localStep = _ScreenStep.management),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () async {
                  await _matrixService.chatBackup.disableChatBackup();
                  _matrixService.skipSetup();
                  if (mounted) context.go('/');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Disable backup'),
              ),
            ],
          ),
      };
    }

    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    return switch (controller.phase) {
      SetupPhase.loading || SetupPhase.verification => const SizedBox.shrink(),
      SetupPhase.savingKey => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () =>
                  setState(() => _localStep = _ScreenStep.skipConfirm),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: !controller.generatingKey && controller.canConfirmNewKey
                  ? controller.confirmNewSsss
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      SetupPhase.unlock => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () =>
                  setState(() => _localStep = _ScreenStep.skipConfirm),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => controller
                  .unlockExistingSsss(_recoveryKeyController.text.trim()),
              child: const Text('Unlock'),
            ),
          ],
        ),
      SetupPhase.done => FilledButton(
          onPressed: _finishSetup,
          child: const Text('Done'),
        ),
      SetupPhase.error => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: controller.retry,
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_controller?.loadingMessage ?? 'Preparing...'),
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
              onPressed: () => controller?.startVerification(),
              icon: const Icon(Icons.devices, size: 18),
              label: const Text('Verify with another device'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                setState(() => _localStep = _ScreenStep.createNewKey),
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
    final verification = _controller?.verification;
    if (verification == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Starting verification...'),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _controller?.onVerificationCancel(),
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
            'Open Kohera on another device and confirm the emoji match.',
          ),
          const SizedBox(height: 24),
          KeyVerificationInline(
            verification: verification,
            onDone: (success) => _controller?.onVerificationDone(success),
            onCancel: () => _controller?.onVerificationCancel(),
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
            onPressed: () =>
                setState(() => _localStep = _ScreenStep.disableConfirm),
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

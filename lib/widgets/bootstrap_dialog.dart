import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption.dart';
import 'package:provider/provider.dart';

import 'dart:async';

import '../services/matrix_service.dart';
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
  Bootstrap? _bootstrap;
  BootstrapState _state = BootstrapState.loading;
  String? _error;
  bool _saveToDevice = false;
  bool _verifying = false;
  late bool _wipeExisting;

  final _recoveryKeyController = TextEditingController();
  String? _recoveryKeyError;
  String? _newRecoveryKey;
  bool _generatingKey = false;
  bool _awaitingKeyAck = false;
  StreamSubscription? _secretStoredSub;

  @override
  void initState() {
    super.initState();
    _wipeExisting = widget.wipeExisting;
    _startBootstrap();
  }

  @override
  void dispose() {
    Clipboard.setData(const ClipboardData(text: ''));
    _newRecoveryKey = null;
    _recoveryKeyController.clear();
    _recoveryKeyController.dispose();
    _secretStoredSub?.cancel();
    super.dispose();
  }

  void _startBootstrap() {
    final encryption = widget.matrixService.client.encryption;
    if (encryption == null) {
      setState(() {
        _state = BootstrapState.error;
        _error = 'Encryption is not available';
      });
      return;
    }

    _bootstrap = encryption.bootstrap(onUpdate: _onBootstrapUpdate);
  }

  void _onBootstrapUpdate(Bootstrap bootstrap) {
    if (!mounted) return;

    _bootstrap = bootstrap;
    final state = bootstrap.state;

    // Auto-advance states that don't need user interaction
    switch (state) {
      case BootstrapState.askWipeSsss:
        bootstrap.wipeSsss(_wipeExisting);
        return;
      case BootstrapState.askWipeCrossSigning:
        bootstrap.wipeCrossSigning(_wipeExisting);
        return;
      case BootstrapState.askSetupCrossSigning:
        bootstrap.askSetupCrossSigning(
          setupMasterKey: true,
          setupSelfSigningKey: true,
          setupUserSigningKey: true,
        );
        return;
      case BootstrapState.askWipeOnlineKeyBackup:
        bootstrap.wipeOnlineKeyBackup(_wipeExisting);
        return;
      case BootstrapState.askSetupOnlineKeyBackup:
        bootstrap.askSetupOnlineKeyBackup(true);
        return;
      case BootstrapState.askBadSsss:
        debugPrint('BootstrapDialog: askBadSsss – ignoring bad secrets');
        bootstrap.ignoreBadSecrets(true);
        return;
      default:
        break;
    }

    // If we're awaiting user acknowledgement of the recovery key,
    // don't let the bootstrap auto-advance the UI state.
    if (_awaitingKeyAck && state != BootstrapState.error) {
      return;
    }

    setState(() {
      _state = state;
      if (state == BootstrapState.askNewSsss) {
        _generateNewSsssKey();
      }
      if (state == BootstrapState.openExistingSsss) {
        _loadStoredRecoveryKey();
      }
    });
  }

  Future<void> _generateNewSsssKey() async {
    setState(() => _generatingKey = true);
    try {
      final bootstrap = _bootstrap;
      if (bootstrap == null) return;
      _awaitingKeyAck = true;
      await bootstrap.newSsss();
      if (!mounted) return;
      setState(() {
        _newRecoveryKey = bootstrap.newSsssKey?.recoveryKey;
        _generatingKey = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generatingKey = false;
        _state = BootstrapState.error;
        _error = 'Failed to generate recovery key: $e';
      });
    }
  }

  Future<void> _loadStoredRecoveryKey() async {
    final storedKey = await widget.matrixService.getStoredRecoveryKey();
    if (storedKey != null && mounted) {
      setState(() {
        _recoveryKeyController.text = storedKey;
      });
    }
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
      case BootstrapState.loading:
      case BootstrapState.askWipeSsss:
      case BootstrapState.askWipeCrossSigning:
      case BootstrapState.askSetupCrossSigning:
      case BootstrapState.askWipeOnlineKeyBackup:
      case BootstrapState.askSetupOnlineKeyBackup:
      case BootstrapState.askBadSsss:
        return 'Setting up backup';
      case BootstrapState.askNewSsss:
        return 'Save your recovery key';
      case BootstrapState.openExistingSsss:
        return 'Enter recovery key';
      case BootstrapState.askUseExistingSsss:
        return 'Existing backup found';
      case BootstrapState.askUnlockSsss:
        return 'Unlock backup';
      case BootstrapState.done:
        return 'Backup complete';
      case BootstrapState.error:
        return 'Backup error';
    }
  }

  Widget _buildContent() {
    switch (_state) {
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
        return _buildNewSsss();

      case BootstrapState.openExistingSsss:
        return _buildOpenExistingSsss();

      case BootstrapState.askUseExistingSsss:
        return _buildAskUseExisting();

      case BootstrapState.askUnlockSsss:
        return _buildUnlockSsss();

      case BootstrapState.done:
        return _buildDone();

      case BootstrapState.error:
        return _buildError();
    }
  }

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

  Widget _buildNewSsss() {
    if (_generatingKey) {
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
            _newRecoveryKey ?? '',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              if (_newRecoveryKey != null) {
                Clipboard.setData(ClipboardData(text: _newRecoveryKey!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ),
        CheckboxListTile(
          value: _saveToDevice,
          onChanged: (v) => setState(() => _saveToDevice = v ?? false),
          title: const Text('Save to device'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildOpenExistingSsss() {
    if (_verifying) {
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
          controller: _recoveryKeyController,
          decoration: InputDecoration(
            labelText: 'Recovery key',
            errorText: _recoveryKeyError,
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _saveToDevice,
          onChanged: (v) => setState(() => _saveToDevice = v ?? false),
          title: const Text('Save to device'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 4),
        const Divider(),
        const SizedBox(height: 4),
        Center(
          child: OutlinedButton.icon(
            onPressed: _verifyWithAnotherDevice,
            icon: const Icon(Icons.devices, size: 18),
            label: const Text('Verify with another device'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _handleLostKey,
          child: const Text('I lost my recovery key'),
        ),
      ],
    );
  }

  Widget _buildAskUseExisting() {
    return const Text(
      'An existing key backup was found. Would you like to use it '
      'or create a new one?',
    );
  }

  Widget _buildUnlockSsss() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Enter your recovery key to unlock your secrets.'),
        const SizedBox(height: 16),
        TextField(
          controller: _recoveryKeyController,
          decoration: InputDecoration(
            labelText: 'Recovery key',
            errorText: _recoveryKeyError,
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Widget _buildDone() {
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

  Widget _buildError() {
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
          _error ?? 'An unexpected error occurred during backup setup.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    switch (_state) {
      case BootstrapState.loading:
      case BootstrapState.askWipeSsss:
      case BootstrapState.askWipeCrossSigning:
      case BootstrapState.askSetupCrossSigning:
      case BootstrapState.askWipeOnlineKeyBackup:
      case BootstrapState.askSetupOnlineKeyBackup:
      case BootstrapState.askBadSsss:
        return [];

      case BootstrapState.askNewSsss:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _generatingKey ? null : _confirmNewSsss,
            child: const Text('Next'),
          ),
        ];

      case BootstrapState.openExistingSsss:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _unlockExistingSsss,
            child: const Text('Unlock'),
          ),
        ];

      case BootstrapState.askUseExistingSsss:
        return [
          TextButton(
            onPressed: () => _bootstrap?.useExistingSsss(false),
            child: const Text('Create new'),
          ),
          FilledButton(
            onPressed: () => _bootstrap?.useExistingSsss(true),
            child: const Text('Use existing backup'),
          ),
        ];

      case BootstrapState.askUnlockSsss:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _unlockOldSsss,
            child: const Text('Unlock'),
          ),
        ];

      case BootstrapState.done:
        return [
          FilledButton(
            onPressed: _onDone,
            child: const Text('Done'),
          ),
        ];

      case BootstrapState.error:
        return [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ];
    }
  }

  void _confirmNewSsss() {
    // Release the gate so bootstrap can advance past askNewSsss
    Clipboard.setData(const ClipboardData(text: ''));
    _awaitingKeyAck = false;
    // The bootstrap has already called newSsss() during _generateNewSsssKey,
    // so we just need to let the onUpdate callback advance normally.
  }

  Future<void> _unlockExistingSsss() async {
    final bootstrap = _bootstrap;
    final ssssKey = bootstrap?.newSsssKey;
    if (ssssKey == null) return;

    final key = _recoveryKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _recoveryKeyError = 'Please enter a recovery key');
      return;
    }

    try {
      await ssssKey.unlock(keyOrPassphrase: key);
    } catch (e) {
      setState(() => _recoveryKeyError = 'Invalid recovery key');
      return;
    }

    setState(() => _recoveryKeyError = null);
    if (_saveToDevice) {
      await widget.matrixService.storeRecoveryKey(key);
    }

    try {
      await bootstrap!.openExistingSsss();
    } catch (e) {
      setState(() {
        _state = BootstrapState.error;
        _error = 'Failed to open backup: $e';
      });
    }
  }

  Future<void> _unlockOldSsss() async {
    final bootstrap = _bootstrap;
    if (bootstrap == null) return;

    final key = _recoveryKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _recoveryKeyError = 'Please enter a recovery key');
      return;
    }

    try {
      final oldKeys = bootstrap.oldSsssKeys;
      if (oldKeys != null) {
        for (final ssssKey in oldKeys.values) {
          await ssssKey.unlock(keyOrPassphrase: key);
        }
      }
      setState(() => _recoveryKeyError = null);
      bootstrap.unlockedSsss();
    } catch (e) {
      setState(() => _recoveryKeyError = 'Invalid recovery key');
    }
  }

  Future<void> _verifyWithAnotherDevice() async {
    final client = widget.matrixService.client;
    final encryption = client.encryption;
    if (encryption == null) return;

    setState(() => _verifying = true);

    try {
      // Refresh device keys
      await client.updateUserDeviceKeys();

      // Listen for secrets being stored (from the verification)
      _secretStoredSub =
          encryption.ssss.onSecretStored.stream.listen((_) async {
        // Secrets were transferred via verification, try to continue bootstrap
        _secretStoredSub?.cancel();
        _secretStoredSub = null;
        if (mounted) {
          setState(() => _verifying = false);
          // Try unlocking with the now-cached secrets
          final bootstrap = _bootstrap;
          final ssssKey = bootstrap?.newSsssKey;
          if (ssssKey != null && ssssKey.isUnlocked) {
            await bootstrap!.openExistingSsss();
          }
        }
      });

      // Create verification request
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
        _secretStoredSub?.cancel();
        _secretStoredSub = null;
        if (mounted) {
          setState(() => _verifying = false);
        }
      }
    } catch (e) {
      _secretStoredSub?.cancel();
      _secretStoredSub = null;
      if (mounted) {
        setState(() {
          _verifying = false;
          _recoveryKeyError = 'Verification failed: ${e.toString()}';
        });
      }
    }
  }

  void _handleLostKey() {
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
              // Restart bootstrap in-place instead of pop+re-show
              setState(() {
                _wipeExisting = true;
                _state = BootstrapState.loading;
                _error = null;
                _newRecoveryKey = null;
                _generatingKey = false;
                _awaitingKeyAck = false;
                _recoveryKeyController.clear();
                _recoveryKeyError = null;
              });
              _startBootstrap();
            },
            child: const Text('Create new backup'),
          ),
        ],
      ),
    );
  }

  Future<void> _onDone() async {
    if (_saveToDevice && _newRecoveryKey != null) {
      await widget.matrixService.storeRecoveryKey(_newRecoveryKey!);
    }
    Clipboard.setData(const ClipboardData(text: ''));
    await widget.matrixService.checkChatBackupStatus();
    if (mounted) {
      Navigator.pop(context, true);
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../extensions/device_extension.dart';
import '../services/matrix_service.dart';
import '../widgets/device_list_item.dart';
import '../widgets/key_verification_dialog.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Device>? _devices;
  bool _loading = true;
  String? _error;
  StreamSubscription? _uiaSub;

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final matrix = context.read<MatrixService>();
    _uiaSub = matrix.onUiaRequest.listen(_showUiaPasswordPrompt);
    _loadDevices();
  }

  @override
  void dispose() {
    _uiaSub?.cancel();
    super.dispose();
  }

  // ── Load Devices ───────────────────────────────────────────

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matrix = context.read<MatrixService>();
      final devices = await matrix.client.getDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Lattice] Failed to load devices: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load devices';
        _loading = false;
      });
    }
  }

  // ── UIA Password Prompt ────────────────────────────────────

  Future<void> _showUiaPasswordPrompt(UiaRequest request) async {
    if (!mounted) return;
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final passwordController = TextEditingController();
        return AlertDialog(
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
        );
      },
    );
    if (password != null && password.isNotEmpty && mounted) {
      context.read<MatrixService>().completeUiaWithPassword(request, password);
    } else {
      request.cancel();
    }
  }

  // ── Rename Device ──────────────────────────────────────────

  Future<void> _renameDevice(Device device) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: device.displayName);
        return AlertDialog(
          title: const Text('Rename device'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Device name',
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
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    if (newName == null || newName.isEmpty) return;

    try {
      if (!mounted) return;
      final client = context.read<MatrixService>().client;
      await client.updateDevice(device.deviceId, displayName: newName);
      await _loadDevices();
    } catch (e) {
      debugPrint('[Lattice] Failed to rename device: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to rename device')),
      );
    }
  }

  // ── Remove Device ──────────────────────────────────────────

  Future<void> _removeDevice(Device device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
          'Remove "${device.displayNameOrId}"? '
          'This will sign out that device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (!mounted) return;
      final client = context.read<MatrixService>().client;
      await client.uiaRequestBackground(
        (auth) => client.deleteDevices([device.deviceId], auth: auth),
      );
      await _loadDevices();
    } catch (e) {
      debugPrint('[Lattice] Failed to remove device: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove device')),
      );
    }
  }

  // ── Remove All Other Devices ───────────────────────────────

  Future<void> _removeAllOtherDevices() async {
    final matrix = context.read<MatrixService>();
    final currentDeviceId = matrix.client.deviceID;
    final otherIds = _devices
            ?.where((d) => d.deviceId != currentDeviceId)
            .map((d) => d.deviceId)
            .toList() ??
        [];
    if (otherIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove all other devices?'),
        content: Text(
          'This will sign out ${otherIds.length} other '
          '${otherIds.length == 1 ? 'device' : 'devices'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final client = matrix.client;
      await client.uiaRequestBackground(
        (auth) => client.deleteDevices(otherIds, auth: auth),
      );
      await _loadDevices();
    } catch (e) {
      debugPrint('[Lattice] Failed to remove devices: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove devices')),
      );
    }
  }

  // ── Verify Device ──────────────────────────────────────────

  Future<void> _verifyDevice(Device device) async {
    final client = context.read<MatrixService>().client;
    final userId = client.userID;
    if (userId == null) return;

    try {
      await client.updateUserDeviceKeys();
      final deviceKeys =
          client.userDeviceKeys[userId]?.deviceKeys[device.deviceId];
      if (deviceKeys == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No encryption keys found for device')),
        );
        return;
      }

      final verification = await deviceKeys.startVerification();
      if (!mounted) return;
      await KeyVerificationDialog.show(context, verification: verification);
      await _loadDevices();
    } catch (e) {
      debugPrint('[Lattice] Failed to start verification: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start verification')),
      );
    }
  }

  // ── Block / Unblock Device ─────────────────────────────────

  Future<void> _toggleBlockDevice(Device device) async {
    final client = context.read<MatrixService>().client;
    final userId = client.userID;
    if (userId == null) return;

    final deviceKeys =
        client.userDeviceKeys[userId]?.deviceKeys[device.deviceId];
    if (deviceKeys == null) return;

    try {
      await deviceKeys.setBlocked(!deviceKeys.blocked);
      await _loadDevices();
    } catch (e) {
      debugPrint('[Lattice] Failed to toggle block: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update device')),
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────

  DeviceKeys? _getDeviceKeys(Device device) {
    final client = context.read<MatrixService>().client;
    final userId = client.userID;
    if (userId == null) return null;
    return client.userDeviceKeys[userId]?.deviceKeys[device.deviceId];
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildError();
    }
    if (_devices == null || _devices!.isEmpty) {
      return const Center(child: Text('No devices found'));
    }

    final matrix = context.read<MatrixService>();
    final currentDeviceId = matrix.client.deviceID;
    final thisDevice =
        _devices!.where((d) => d.deviceId == currentDeviceId).toList();
    final otherDevices =
        _devices!.where((d) => d.deviceId != currentDeviceId).toList()
          ..sort((a, b) {
            final aTs = a.lastSeenTs ?? 0;
            final bTs = b.lastSeenTs ?? 0;
            return bTs.compareTo(aTs);
          });

    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _loadDevices,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Chat backup warning
          if (matrix.chatBackupNeeded == true) ...[
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Chat backup is not set up. Device verification '
                        'may not work correctly without it.',
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── This Device ──
          if (thisDevice.isNotEmpty) ...[
            const _SectionHeader(label: 'THIS DEVICE'),
            Card(
              child: DeviceListItem(
                device: thisDevice.first,
                isCurrentDevice: true,
                deviceKeys: _getDeviceKeys(thisDevice.first),
                onRename: () => _renameDevice(thisDevice.first),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Other Devices ──
          const _SectionHeader(label: 'OTHER DEVICES'),
          if (otherDevices.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No other devices found',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else ...[
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < otherDevices.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    DeviceListItem(
                      device: otherDevices[i],
                      isCurrentDevice: false,
                      deviceKeys: _getDeviceKeys(otherDevices[i]),
                      onRename: () => _renameDevice(otherDevices[i]),
                      onVerify: () => _verifyDevice(otherDevices[i]),
                      onToggleBlock: () => _toggleBlockDevice(otherDevices[i]),
                      onRemove: () => _removeDevice(otherDevices[i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _removeAllOtherDevices,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Remove all other devices'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),
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
          Icon(Icons.error_outline, size: 48, color: cs.error),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: cs.error)),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _loadDevices,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Private Section Header ───────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(
          color: cs.primary,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

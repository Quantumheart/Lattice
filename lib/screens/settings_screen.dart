import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/client_manager.dart';
import '../services/matrix_service.dart';
import '../widgets/bootstrap_dialog.dart';
import 'devices_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _lastShownError;

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final manager = context.watch<ClientManager>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final client = matrix.client;

    // Surface backup errors via SnackBar.
    final error = matrix.chatBackupError;
    if (error != null && error != _lastShownError) {
      _lastShownError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      });
    } else if (error == null) {
      _lastShownError = null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Account card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      (client.userID != null && client.userID!.length > 1)
                          ? client.userID![1].toUpperCase()
                          : (client.userID ?? '?')[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.userID ?? 'Unknown',
                          style: tt.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          client.homeserver.toString(),
                          style: tt.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Account Switcher ──
          if (manager.hasMultipleAccounts) ...[
            const SizedBox(height: 16),
            const _SectionHeader(label: 'ACCOUNTS'),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < manager.services.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: i == manager.activeIndex
                            ? cs.primary
                            : cs.surfaceContainerHigh,
                        child: Text(
                          _userInitial(manager.services[i].client.userID),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: i == manager.activeIndex
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      title: Text(
                        manager.services[i].client.userID ?? 'Unknown',
                        style: i == manager.activeIndex
                            ? tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
                            : null,
                      ),
                      trailing: i == manager.activeIndex
                          ? Icon(Icons.check, color: cs.primary)
                          : null,
                      onTap: () {
                        manager.setActiveAccount(i);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Add Account ──
          OutlinedButton.icon(
            onPressed: () => _addAccount(context, manager),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Add account'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Preferences ──
          const _SectionHeader(label: 'PREFERENCES'),
          Card(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Theme',
                  subtitle: 'System default',
                  onTap: () {
                    // TODO: theme picker
                  },
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Enabled',
                  onTap: () {
                    // TODO: notification settings
                  },
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.text_fields_rounded,
                  title: 'Message density',
                  subtitle: 'Default',
                  onTap: () {
                    // TODO: density picker
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Security ──
          const _SectionHeader(label: 'SECURITY'),
          Card(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.cloud_outlined,
                  title: 'Chat backup',
                  subtitle: matrix.chatBackupLoading
                      ? 'Setting up…'
                      : matrix.chatBackupNeeded == null
                          ? 'Checking...'
                          : matrix.chatBackupEnabled
                              ? 'Your keys are backed up'
                              : 'Not set up',
                  onTap: matrix.chatBackupLoading
                      ? () {}
                      : () => matrix.chatBackupEnabled
                          ? _showBackupInfo(context)
                          : BootstrapDialog.show(context),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.devices_rounded,
                  title: 'Devices',
                  subtitle: 'Manage your devices',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DevicesScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── About ──
          const _SectionHeader(label: 'ABOUT'),
          Card(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Lattice',
                  subtitle: 'v1.0.0 • Built with Flutter',
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.code_rounded,
                  title: 'Source code',
                  subtitle: 'View on GitHub',
                  onTap: () {
                    launchUrl(Uri.parse('https://github.com/Quantumheart/Lattice'));
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Logout ──
          FilledButton.tonal(
            onPressed: () => _confirmLogout(context),
            style: FilledButton.styleFrom(
              backgroundColor: cs.errorContainer,
              foregroundColor: cs.onErrorContainer,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Sign Out'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showBackupInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chat backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: Theme.of(ctx).colorScheme.primary,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your keys are backed up. Your encrypted messages are '
              'secure and accessible from any device.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDisableBackup(context);
            },
            child: Text(
              'Disable backup',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _confirmDisableBackup(BuildContext context) {
    final matrix = context.read<MatrixService>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DisableBackupDialog(matrix: matrix),
    );
  }

  Future<void> _addAccount(BuildContext context, ClientManager manager) async {
    final service = await manager.createLoginService();
    await manager.addService(service);
    if (context.mounted) Navigator.pop(context);
  }

  String _userInitial(String? userId) {
    if (userId != null && userId.length > 1) return userId[1].toUpperCase();
    return (userId ?? '?')[0].toUpperCase();
  }

  void _confirmLogout(BuildContext context) {
    final matrix = context.read<MatrixService>();
    final manager = context.read<ClientManager>();
    final backupMissing = !matrix.chatBackupEnabled;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (backupMissing) ...[
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Theme.of(ctx).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your encryption keys are not backed up. You will '
                      'permanently lose access to your encrypted messages.',
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'You will need to sign in again to access your messages.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (backupMissing)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                BootstrapDialog.show(context);
              },
              child: const Text('Set up backup first'),
            ),
          FilledButton(
            style: backupMissing
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  )
                : null,
            onPressed: () async {
              final nav = Navigator.of(context);
              Navigator.pop(ctx);
              await matrix.logout();
              await manager.removeService(matrix);
              if (nav.canPop()) nav.pop();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

}

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

class _DisableBackupDialog extends StatefulWidget {
  const _DisableBackupDialog({required this.matrix});
  final MatrixService matrix;

  @override
  State<_DisableBackupDialog> createState() => _DisableBackupDialogState();
}

class _DisableBackupDialogState extends State<_DisableBackupDialog> {
  bool _disabling = false;

  Future<void> _disable() async {
    setState(() => _disabling = true);
    await widget.matrix.disableChatBackup();
    if (!mounted) return;
    Navigator.pop(context);
    if (widget.matrix.chatBackupError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.matrix.chatBackupError!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Disable chat backup?'),
      content: _disabling
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Disabling backup…'),
              ],
            )
          : const Text(
              'You will lose access to your encrypted message history '
              'on new devices unless you set up backup again.',
            ),
      actions: _disabling
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                onPressed: _disable,
                child: const Text('Disable'),
              ),
            ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

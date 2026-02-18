import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final client = matrix.client;

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
                SwitchListTile(
                  secondary: Icon(Icons.cloud_outlined,
                      color: cs.onSurfaceVariant),
                  title: const Text('Chat backup'),
                  subtitle: Text(
                    matrix.chatBackupLoading
                        ? 'Setting up...'
                        : matrix.chatBackupEnabled
                            ? 'Your keys are backed up'
                            : 'Off',
                  ),
                  value: matrix.chatBackupEnabled,
                  onChanged: matrix.chatBackupLoading
                      ? null
                      : (v) => _handleBackupToggle(context, v),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.devices_rounded,
                  title: 'Sessions',
                  subtitle: 'View active sessions',
                  onTap: () {
                    // TODO: session management
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
                    // TODO: open GitHub
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

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to access your messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final nav = Navigator.of(context);
              if (nav.canPop()) nav.pop();
              context.read<MatrixService>().logout();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBackupToggle(BuildContext context, bool enable) async {
    final matrix = context.read<MatrixService>();
    if (enable) {
      final recoveryKey = await matrix.enableChatBackup();
      if (!context.mounted) return;
      if (recoveryKey != null) {
        _showRecoveryKeyDialog(context, recoveryKey);
      } else if (matrix.chatBackupError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(matrix.chatBackupError!)),
        );
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Disable chat backup?'),
          content: const Text(
            'You will lose the ability to recover encrypted messages '
            'on new devices. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disable'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await matrix.disableChatBackup();
        if (!context.mounted) return;
        if (matrix.chatBackupError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(matrix.chatBackupError!)),
          );
        }
      }
    }
  }

  void _showRecoveryKeyDialog(BuildContext context, String recoveryKey) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Save your recovery key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                recoveryKey,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: recoveryKey));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('I saved my key'),
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

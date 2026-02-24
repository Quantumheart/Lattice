import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/client_manager.dart';
import '../services/matrix_service.dart';
import '../services/preferences_service.dart';
import '../widgets/bootstrap_dialog.dart';
import '../widgets/user_avatar.dart';
import 'devices_screen.dart';
import 'notification_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _lastShownError;
  bool _avatarUploading = false;
  Uri? _avatarUrl;
  String? _displayName;
  final _displayNameController = TextEditingController();
  bool _displayNameSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    try {
      final client = context.read<MatrixService>().client;
      final profile = await client.fetchOwnProfile();
      if (mounted) {
        setState(() {
          _avatarUrl = profile.avatarUrl;
          _displayName = profile.displayName;
          _displayNameController.text = profile.displayName ?? '';
        });
      }
    } catch (e) {
      debugPrint('[Lattice] Failed to fetch profile: $e');
    }
  }

  Future<void> _saveDisplayName() async {
    final newName = _displayNameController.text.trim();
    if (newName == (_displayName ?? '')) return;

    final client = context.read<MatrixService>().client;
    setState(() => _displayNameSaving = true);
    try {
      await client.setProfileField(
        client.userID!, 'displayname', {'displayname': newName},
      );
      debugPrint('[Lattice] Display name updated to: $newName');
      await _fetchProfile();
    } catch (e) {
      debugPrint('[Lattice] Display name update failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update display name: ${MatrixService.friendlyAuthError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _displayNameSaving = false);
    }
  }

  Future<void> _uploadAvatar() async {
    final client = context.read<MatrixService>().client;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _avatarUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      await client.setAvatar(MatrixFile(bytes: bytes, name: picked.name));
      debugPrint('[Lattice] Avatar uploaded: ${picked.name} (${bytes.length} bytes)');
      await _fetchProfile();
    } catch (e) {
      debugPrint('[Lattice] Avatar upload failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload avatar: ${MatrixService.friendlyAuthError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  Future<void> _removeAvatar() async {
    final client = context.read<MatrixService>().client;
    setState(() => _avatarUploading = true);
    try {
      await client.setAvatar(null);
      debugPrint('[Lattice] Avatar removed');
      await _fetchProfile();
    } catch (e) {
      debugPrint('[Lattice] Avatar removal failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove avatar: ${MatrixService.friendlyAuthError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final manager = context.watch<ClientManager>();
    final prefs = context.watch<PreferencesService>();
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
              child: Column(
                children: [
                  Row(
                    children: [
                      Stack(
                        children: [
                          UserAvatar(
                            client: client,
                            avatarUrl: _avatarUrl,
                            userId: client.userID,
                            size: 56,
                          ),
                          if (_avatarUploading)
                            const Positioned.fill(
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_displayName != null && _displayName!.isNotEmpty)
                              Text(
                                _displayName!,
                                style: tt.titleMedium,
                              ),
                            const SizedBox(height: 2),
                            Text(
                              client.userID ?? 'Unknown',
                              style: _displayName != null && _displayName!.isNotEmpty
                                  ? tt.bodyMedium
                                  : tt.titleMedium,
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _displayNameController,
                          enabled: !_displayNameSaving,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _saveDisplayName(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _displayNameSaving ? null : _saveDisplayName,
                        icon: _displayNameSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded),
                        tooltip: 'Save display name',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _avatarUploading ? null : _uploadAvatar,
                        icon: const Icon(Icons.photo_library_outlined,
                            size: 18),
                        label: const Text('Upload avatar'),
                      ),
                      if (_avatarUrl != null) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _avatarUploading ? null : _removeAvatar,
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: cs.error),
                          label: Text('Remove',
                              style: TextStyle(color: cs.error)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                          ),
                        ),
                      ],
                    ],
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
                      leading: UserAvatar(
                        client: manager.services[i].client,
                        userId: manager.services[i].client.userID,
                        size: 36,
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
                      mouseCursor: SystemMouseCursors.click,
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
                  subtitle: prefs.themeModeLabel,
                  onTap: () => _showThemePicker(context),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: prefs.notificationLevelLabel,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.text_fields_rounded,
                  title: 'Message density',
                  subtitle: prefs.messageDensity.label,
                  onTap: () => _showDensityPicker(context),
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

  void _showThemePicker(BuildContext context) {
    final prefs = context.read<PreferencesService>();
    final options = [
      (ThemeMode.system, 'System default'),
      (ThemeMode.light, 'Light'),
      (ThemeMode.dark, 'Dark'),
    ];
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Theme'),
          contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
          content: RadioGroup<ThemeMode>(
            groupValue: prefs.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) {
                prefs.setThemeMode(value);
                Navigator.pop(ctx);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((option) {
                final (mode, label) = option;
                return RadioListTile<ThemeMode>(
                  title: Text(label),
                  value: mode,
                  mouseCursor: SystemMouseCursors.click,
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showDensityPicker(BuildContext context) {
    final prefs = context.read<PreferencesService>();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Message density'),
          contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
          content: RadioGroup<MessageDensity>(
            groupValue: prefs.messageDensity,
            onChanged: (MessageDensity? value) {
              if (value != null) {
                prefs.setMessageDensity(value);
                Navigator.pop(ctx);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: MessageDensity.values.map((density) {
                return RadioListTile<MessageDensity>(
                  title: Text(density.label),
                  value: density,
                  mouseCursor: SystemMouseCursors.click,
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
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
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
    );
  }
}

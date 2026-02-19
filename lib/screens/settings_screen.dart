import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';

import '../services/matrix_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Uri? _avatarUrl;
  String? _displayName;
  bool _loadingProfile = true;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final matrix = context.read<MatrixService>();
    try {
      final profile = await matrix.fetchOwnProfile();
      if (!mounted) return;
      setState(() {
        _avatarUrl = profile.avatarUrl;
        _displayName = profile.displayname;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final matrix = context.read<MatrixService>();
      await matrix.setAvatar(bytes, filename: picked.name);
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update avatar: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final client = matrix.client;

    final initial = (client.userID != null && client.userID!.length > 1)
        ? client.userID![1].toUpperCase()
        : (client.userID ?? '?')[0].toUpperCase();

    final thumbnailUrl = matrix.avatarThumbnailUrl(_avatarUrl, dimension: 128);

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
                  GestureDetector(
                    onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                    child: Stack(
                      children: [
                        _buildAvatar(cs, initial, thumbnailUrl),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.camera_alt,
                              size: 14,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                        if (_uploadingAvatar)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
                        Text(
                          client.userID ?? 'Unknown',
                          style: _displayName != null
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
                  icon: Icons.key_rounded,
                  title: 'Encryption keys',
                  subtitle: 'Manage cross-signing',
                  onTap: () {
                    // TODO: key management
                  },
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

  Widget _buildAvatar(ColorScheme cs, String initial, Uri? thumbnailUrl) {
    if (_loadingProfile) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: cs.primaryContainer,
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: cs.onPrimaryContainer,
          ),
        ),
      );
    }

    if (thumbnailUrl != null) {
      return CachedNetworkImage(
        imageUrl: thumbnailUrl.toString(),
        imageBuilder: (_, imageProvider) => CircleAvatar(
          radius: 28,
          backgroundImage: imageProvider,
        ),
        placeholder: (_, __) => CircleAvatar(
          radius: 28,
          backgroundColor: cs.primaryContainer,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _initialAvatar(cs, initial),
      );
    }

    return _initialAvatar(cs, initial);
  }

  Widget _initialAvatar(ColorScheme cs, String initial) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: cs.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: cs.onPrimaryContainer,
        ),
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
              context.read<MatrixService>().logout();
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

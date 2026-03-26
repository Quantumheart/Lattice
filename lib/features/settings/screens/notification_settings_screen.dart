import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/notifications/services/push_service.dart';
import 'package:lattice/shared/widgets/section_header.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _keywordController = TextEditingController();
  final _keywordFocus = FocusNode();

  @override
  void dispose() {
    _keywordController.dispose();
    _keywordFocus.dispose();
    super.dispose();
  }

  // ── Keyword actions ─────────────────────────────────────────

  void _addKeyword() {
    final text = _keywordController.text;
    if (text.trim().isEmpty) return;
    unawaited(context.read<PreferencesService>().addNotificationKeyword(text));
    _keywordController.clear();
    _keywordFocus.requestFocus();
  }

  // ── Push settings ──────────────────────────────────────────

  static bool get _showPushSettings => !kIsWeb && Platform.isAndroid;

  static const List<({String name, String package, String description, String url})> _distributors = [
    (
      name: 'ntfy',
      package: 'io.heckel.ntfy',
      description: 'Lightweight, self-hostable push service',
      url: 'https://f-droid.org/packages/io.heckel.ntfy/',
    ),
    (
      name: 'NextPush',
      package: 'org.unifiedpush.distributor.nextpush',
      description: 'Push via Nextcloud server',
      url: 'https://f-droid.org/packages/org.unifiedpush.distributor.nextpush/',
    ),
  ];

  Future<void> _setupDistributor() async {
    final pushService = context.read<PushService>();
    final prefs = context.read<PreferencesService>();
    final installed = await pushService.getDistributors();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Push distributor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _distributors.map((d) {
            final isInstalled = installed.any((i) => i.contains(d.package));
            return ListTile(
              title: Text(d.name),
              subtitle: Text(
                isInstalled ? 'Installed' : d.description,
              ),
              trailing: isInstalled
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : TextButton(
                      onPressed: () => unawaited(
                        launchUrl(
                            Uri.parse(d.url),
                            mode: LaunchMode.externalApplication,
                        ),
                      ),
                      child: const Text('Install'),
                    ),
              onTap: isInstalled
                  ? () {
                      final match = installed
                          .firstWhere((i) => i.contains(d.package));
                      unawaited(pushService.selectDistributor(match));
                      Navigator.of(ctx).pop();
                    }
                  : null,
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (mounted && prefs.pushDistributor != null) {
      unawaited(prefs.setPushEnabled(true));
      unawaited(pushService.register());
    }
  }


  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final keywords = prefs.notificationKeywords;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(Routes.settings),
        ),
        title: const Text('Notifications'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Notification level ──────────────────────────────
          const SectionHeader(label: 'NOTIFICATION LEVEL'),
          Card(
            child: RadioGroup<NotificationLevel>(
              groupValue: prefs.notificationLevel,
              onChanged: (v) => prefs.setNotificationLevel(v!),
              child: const Column(
                children: [
                  RadioListTile<NotificationLevel>(
                    title: Text('All messages'),
                    value: NotificationLevel.all,
                  ),
                  RadioListTile<NotificationLevel>(
                    title: Text('Mentions & keywords only'),
                    value: NotificationLevel.mentionsOnly,
                  ),
                  RadioListTile<NotificationLevel>(
                    title: Text('Off'),
                    value: NotificationLevel.off,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 24),
            child: Text(
              'Controls which messages show in-app unread indicators. '
              'Per-room server settings are not affected.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),

          // ── Custom keywords ─────────────────────────────────
          const SectionHeader(label: 'CUSTOM KEYWORDS'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Get notified when messages contain these words',
                    style: tt.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _keywordController,
                          focusNode: _keywordFocus,
                          decoration: const InputDecoration(
                            labelText: 'Add keyword',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addKeyword(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _addKeyword,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (keywords.isEmpty)
                    Text(
                      'No custom keywords added',
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: keywords
                          .map(
                            (kw) => InputChip(
                              label: Text(kw),
                              onDeleted: () =>
                                  prefs.removeNotificationKeyword(kw),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── OS notifications ─────────────────────────────────
          const SectionHeader(label: 'OS NOTIFICATIONS'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Enable OS notifications'),
                  subtitle:
                      const Text('Show system notifications for new messages'),
                  value: prefs.osNotificationsEnabled,
                  onChanged: prefs.setOsNotificationsEnabled,
                ),
                SwitchListTile(
                  title: const Text('Notification sound'),
                  value: prefs.notificationSoundEnabled,
                  onChanged: prefs.osNotificationsEnabled
                      ? prefs.setNotificationSoundEnabled
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Vibration'),
                  subtitle: const Text('No effect on desktop'),
                  value: prefs.notificationVibrationEnabled,
                  onChanged: prefs.osNotificationsEnabled
                      ? prefs.setNotificationVibrationEnabled
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Foreground notifications'),
                  subtitle: const Text(
                    'Show notifications for unfocused rooms while app is open',
                  ),
                  value: prefs.foregroundNotificationsEnabled,
                  onChanged: prefs.osNotificationsEnabled
                      ? prefs.setForegroundNotificationsEnabled
                      : null,
                ),
              ],
            ),
          ),

          // ── Push notifications (Android only) ────────────────
          if (_showPushSettings) ...[
            const SizedBox(height: 24),
            const SectionHeader(label: 'BACKGROUND PUSH'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Background push notifications'),
                    subtitle: Text(
                      prefs.pushEnabled
                          ? 'Via ${prefs.pushDistributor?.split('.').last ?? 'UnifiedPush'}'
                          : 'Receive notifications when the app is closed',
                    ),
                    value: prefs.pushEnabled,
                    onChanged: (value) {
                      if (value) {
                        unawaited(_setupDistributor());
                      } else {
                        final pushService = context.read<PushService>();
                        unawaited(prefs.setPushEnabled(false));
                        unawaited(pushService.unregister());
                      }
                    },
                  ),
                  if (prefs.pushEnabled)
                    ListTile(
                      title: const Text('Change distributor'),
                      subtitle: Text(
                        prefs.pushDistributor?.split('.').last ?? 'None',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _setupDistributor,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

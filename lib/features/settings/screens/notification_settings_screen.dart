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

  // ── Push settings dialogs ──────────────────────────────────

  static bool get _showPushSettings => !kIsWeb && Platform.isAndroid;

  Future<void> _showDistributorPicker() async {
    final pushService = context.read<PushService>();
    final distributors = await pushService.getDistributors();
    if (!mounted || distributors.isEmpty) return;

    final prefs = context.read<PreferencesService>();
    final current = prefs.pushDistributor;

    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select push distributor'),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (value) {
              if (value != null) {
                unawaited(pushService.selectDistributor(value));
                Navigator.of(ctx).pop();
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: distributors
                  .map(
                    (d) => RadioListTile<String>(
                      title: Text(d.split('.').last),
                      subtitle: Text(d, overflow: TextOverflow.ellipsis),
                      value: d,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
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
            const SectionHeader(label: 'PUSH NOTIFICATIONS'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Enable push notifications'),
                    subtitle: const Text(
                      'Receive notifications when the app is closed',
                    ),
                    value: prefs.pushEnabled,
                    onChanged: (value) {
                      final pushService = context.read<PushService>();
                      unawaited(prefs.setPushEnabled(value));
                      if (value) {
                        unawaited(pushService.register());
                      } else {
                        unawaited(pushService.unregister());
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('Distributor'),
                    subtitle: Text(
                      prefs.pushDistributor?.split('.').last ?? 'Default',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: prefs.pushEnabled,
                    onTap: prefs.pushEnabled ? _showDistributorPicker : null,
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

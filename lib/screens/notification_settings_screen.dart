import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/preferences_service.dart';

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
    context.read<PreferencesService>().addNotificationKeyword(text);
    _keywordController.clear();
    _keywordFocus.requestFocus();
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final keywords = prefs.notificationKeywords;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Notification level ──────────────────────────────
          const _SectionHeader(label: 'NOTIFICATION LEVEL'),
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
          const _SectionHeader(label: 'CUSTOM KEYWORDS'),
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
        ],
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────

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

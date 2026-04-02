import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/settings/widgets/custom_theme_editor.dart';
import 'package:lattice/features/settings/widgets/theme_preset_picker.dart';
import 'package:lattice/shared/widgets/section_header.dart';
import 'package:provider/provider.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(Routes.settings),
        ),
        title: const Text('Appearance'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Theme ──────────────────────────────────────────
          const SectionHeader(label: 'THEME'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose your preferred color scheme.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  const ThemePresetPicker(),
                  if (prefs.themePreset == 'custom')
                    const CustomThemeEditor(),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Message density ────────────────────────────────
          const SectionHeader(label: 'MESSAGE DENSITY'),
          Card(
            child: RadioGroup<MessageDensity>(
              groupValue: prefs.messageDensity,
              onChanged: (v) => prefs.setMessageDensity(v!),
              child: Column(
                children: MessageDensity.values.map((density) {
                  return RadioListTile<MessageDensity>(
                    title: Text(density.label),
                    value: density,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

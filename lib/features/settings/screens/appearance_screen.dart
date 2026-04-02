import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/settings/widgets/accent_color_picker.dart';
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
          // ── Theme mode ──────────────────────────────────────
          const SectionHeader(label: 'THEME'),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: prefs.themeMode,
              onChanged: (v) => prefs.setThemeMode(v!),
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text('System default'),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('Light'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('Dark'),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Accent color ────────────────────────────────────
          const SectionHeader(label: 'ACCENT COLOR'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose a color or let your system decide.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  const AccentColorPicker(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

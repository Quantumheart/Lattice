import 'package:flutter/material.dart';

class AppLogoHeader extends StatelessWidget {
  const AppLogoHeader({super.key, required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Logo ──
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.hub_rounded,
            size: 36,
            color: cs.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 20),
        Text('Lattice', style: tt.displayLarge),
        const SizedBox(height: 4),
        Text(subtitle, style: tt.bodyMedium),
        const SizedBox(height: 40),
      ],
    );
  }
}

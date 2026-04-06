import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:provider/provider.dart';

class KeyBackupBanner extends StatelessWidget {
  const KeyBackupBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final needed = context.select<MatrixService, bool?>(
      (m) => m.chatBackupNeeded,
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: needed == true
          ? const _KeyBackupBannerContent()
          : const SizedBox.shrink(),
    );
  }
}

class _KeyBackupBannerContent extends StatelessWidget {
  const _KeyBackupBannerContent();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      label: 'Key backup not set up. Tap to configure.',
      button: true,
      child: InkWell(
        onTap: () => context.go('/e2ee-setup'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: cs.tertiary, width: 3)),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: cs.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Protect your messages',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.tertiary,
                      ),
                    ),
                    Text(
                      'Without key backup, you may lose message history '
                      'and some features will not work',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.go('/e2ee-setup'),
                child: const Text('Set up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

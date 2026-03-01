import 'package:flutter/material.dart';

import '../services/matrix_service.dart';
import 'section_header.dart';
import 'user_avatar.dart';

/// Displays the list of logged-in accounts with an active-account indicator
/// and tap-to-switch behavior.
class AccountSwitcher extends StatelessWidget {
  const AccountSwitcher({
    super.key,
    required this.services,
    required this.activeIndex,
    required this.onAccountTapped,
  });

  final List<MatrixService> services;
  final int activeIndex;
  final ValueChanged<int> onAccountTapped;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(label: 'ACCOUNTS'),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < services.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                ListTile(
                  leading: UserAvatar(
                    client: services[i].client,
                    userId: services[i].client.userID,
                    size: 36,
                  ),
                  title: Text(
                    services[i].client.userID ?? 'Unknown',
                    style: i == activeIndex
                        ? tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
                        : null,
                  ),
                  trailing: i == activeIndex
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () => onAccountTapped(i),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

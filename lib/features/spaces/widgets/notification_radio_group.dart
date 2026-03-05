import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Reusable radio-button group for selecting a [PushRuleState].
///
/// Used in both the space context-menu dialog and the space details panel.
/// Pass [onChanged] as `null` to disable interaction (tiles appear dimmed).
class NotificationRadioGroup extends StatelessWidget {
  const NotificationRadioGroup({
    super.key,
    required this.groupValue,
    this.onChanged,
  });

  final PushRuleState groupValue;
  final ValueChanged<PushRuleState?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    Widget group = RadioGroup<PushRuleState>(
      groupValue: groupValue,
      onChanged: onChanged ?? (_) {},
      child: const Column(
        children: [
          RadioListTile<PushRuleState>(
            title: Text('All messages'),
            value: PushRuleState.notify,
          ),
          RadioListTile<PushRuleState>(
            title: Text('Mentions only'),
            value: PushRuleState.mentionsOnly,
          ),
          RadioListTile<PushRuleState>(
            title: Text('Muted'),
            value: PushRuleState.dontNotify,
          ),
        ],
      ),
    );
    if (!enabled) {
      group = Opacity(opacity: 0.5, child: AbsorbPointer(child: group));
    }
    return group;
  }
}

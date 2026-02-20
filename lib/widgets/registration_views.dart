import 'package:flutter/material.dart';

import 'registration_controller.dart';

/// Builds content for UIA stages that appear after form submission.
Widget buildUiaContent({
  required BuildContext context,
  required RegistrationController controller,
}) {
  switch (controller.state) {
    case RegistrationState.enterEmail:
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Email verification is required by this server.'),
          SizedBox(height: 8),
          Text('This step is not yet supported.'),
        ],
      );

    case RegistrationState.recaptcha:
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('CAPTCHA verification is required by this server.'),
          SizedBox(height: 8),
          Text('This step is not yet supported.'),
        ],
      );

    case RegistrationState.acceptTerms:
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('You must accept the terms of service.'),
          SizedBox(height: 8),
          Text('This step is not yet supported.'),
        ],
      );

    default:
      return const SizedBox.shrink();
  }
}

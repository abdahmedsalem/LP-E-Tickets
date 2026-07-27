import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authentication and client secondary screens use localization', () {
    final paths = <String>[
      'lib/features/auth/screens/activation_pending_screen.dart',
      'lib/features/auth/screens/forgot_otp_flow_screens.dart',
      'lib/features/auth/screens/forgot_password_screen.dart',
      'lib/features/auth/screens/login_screen.dart',
      'lib/features/auth/screens/onboarding_screen.dart',
      'lib/features/auth/screens/register_screen.dart',
      'lib/features/auth/screens/register_verify_otp_screen.dart',
      'lib/features/auth/screens/session_pin_lock_screen.dart',
      'lib/features/auth/screens/splash_screen.dart',
      'lib/features/settings/screens/acpec_connection_step1_screen.dart',
      'lib/features/settings/screens/acpec_signup_step2_screen.dart',
      'lib/features/settings/screens/notifications_screen.dart',
      'lib/features/settings/screens/settings_screen.dart',
      'lib/shared/widgets/api_required_view.dart',
      'lib/shared/widgets/auth_action_code_dialog.dart',
      'lib/shared/widgets/backend_unavailable_banner.dart',
      'lib/shared/widgets/list_filters_sheet.dart',
      'lib/shared/widgets/wallet_breakdown_sheet.dart',
    ];

    for (final path in paths) {
      expect(
        File(path).readAsStringSync(),
        contains('AppLocalizations'),
        reason: path,
      );
    }
  });

  test('authentication form alignments remain RTL aware', () {
    for (final path in <String>[
      'lib/features/auth/screens/login_screen.dart',
      'lib/features/auth/screens/register_screen.dart',
      'lib/features/auth/screens/register_verify_otp_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('Alignment.centerRight')), reason: path);
      expect(source, isNot(contains('TextAlign.left')), reason: path);
    }
  });
}

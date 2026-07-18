import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared card title keeps the complete text on one line', () {
    final source = File(
      'lib/shared/widgets/single_line_card_title.dart',
    ).readAsStringSync();

    expect(source, contains('fit: BoxFit.scaleDown'));
    expect(source, contains('maxLines: 1'));
    expect(source, contains('softWrap: false'));
    expect(source, isNot(contains('TextOverflow.ellipsis')));
  });

  test('card-based screens use the shared single-line title', () {
    const paths = <String>[
      'lib/features/admin/screens/admin_home_screen.dart',
      'lib/features/auth/screens/language_selection_screen.dart',
      'lib/features/home/screens/faces_detail_screen.dart',
      'lib/features/home/screens/user_home_screen.dart',
      'lib/features/purchases/screens/purchase_detail_screen.dart',
      'lib/features/purchases/screens/purchases_list_screen.dart',
      'lib/features/purchases/screens/submit_purchase_screen.dart',
      'lib/features/qr/screens/emit_qr_screen.dart',
      'lib/features/qr/screens/qr_detail_screen.dart',
      'lib/features/qr/screens/retirer_qr_screen.dart',
      'lib/features/qr/screens/transfer_carnets_screen.dart',
      'lib/features/qr/screens/transfer_confirmation_screen.dart',
      'lib/features/qr/screens/transfer_tickets_screen.dart',
      'lib/features/settings/screens/notifications_screen.dart',
      'lib/features/settings/screens/settings_screen.dart',
      'lib/features/station/screens/station_consumption_history_screen.dart',
      'lib/features/station/screens/station_home_screen.dart',
      'lib/features/station/screens/station_profile_screen.dart',
      'lib/features/transactions/screens/transactions_screen.dart',
      'lib/shared/widgets/qr_generation_carnet_line.dart',
      'lib/shared/widgets/quick_action.dart',
      'lib/shared/widgets/transfer_line_row.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('SingleLineCardTitle('),
        reason: '$path must use the shared complete card title',
      );
    }
  });
}

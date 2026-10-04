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
      'lib/features/auth/screens/language_selection_screen.dart',
      'lib/features/portfolio/screens/faces_detail_screen.dart',
      'lib/features/home/screens/user_home_screen.dart',
      'lib/features/purchases/screens/submit_purchase_screen.dart',
      'lib/features/qr/generation/screens/emit_qr_screen.dart',
      'lib/features/qr/detail/screens/qr_detail_screen.dart',
      'lib/features/qr/retirer/screens/retirer_qr_screen.dart',
      'lib/features/transfer/widgets/transfer_carnet_line_card.dart',
      'lib/features/transfer/widgets/transfer_confirmation_content.dart',
      'lib/features/transfer/widgets/transfer_ticket_line_card.dart',
      'lib/features/settings/screens/notifications_screen.dart',
      'lib/features/profile/screens/client_profile_screen.dart',
      'lib/features/station/accueil/station_home_screen.dart',
      'lib/features/station/profile/station_profile_screen.dart',
      'lib/features/history/screens/transactions_screen.dart',
      'lib/shared/widgets/confirmation_line_main_row.dart',
      'lib/shared/widgets/quick_action.dart',
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

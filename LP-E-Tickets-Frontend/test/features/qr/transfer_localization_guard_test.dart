import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('transfer flow localization', () {
    final carnets = File(
      'lib/features/qr/screens/transfer_carnets_screen.dart',
    ).readAsStringSync();
    final tickets = File(
      'lib/features/qr/screens/transfer_tickets_screen.dart',
    ).readAsStringSync();
    final confirmation = File(
      'lib/features/qr/screens/transfer_confirmation_screen.dart',
    ).readAsStringSync();
    final success = File(
      'lib/shared/widgets/purchase_submit_success_dialog.dart',
    ).readAsStringSync();

    test('selection screens use localized user-facing labels', () {
      expect(carnets, contains('l10n.transferConfirmTitle'));
      expect(carnets, contains('transferCarnetsInstruction'));
      expect(carnets, isNot(contains("title: 'Transfert de carnets'")));

      expect(tickets, contains('l10n.transferConfirmTitle'));
      expect(tickets, contains('transferTicketsInstruction'));
      expect(tickets, isNot(contains("title: 'Transfert de tickets'")));
    });

    test('confirmation and success screens are localized and RTL-safe', () {
      expect(confirmation, contains('commonPinVerification'));
      expect(confirmation, contains('transferFinalDisclaimer'));
      expect(confirmation, isNot(contains("'Bénéficiaire'")));

      expect(success, contains('l10n.transferSuccessTitle'));
      expect(success, contains('showQuantity: showQuantity'));
      expect(success, isNot(contains("title: 'Transfert confirmé'")));
    });
  });
}

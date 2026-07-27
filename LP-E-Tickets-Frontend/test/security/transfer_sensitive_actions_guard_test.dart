import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2L3A transfer sensitive actions guard', () {
    test('carnet transfer parent has a real mutable submit lock', () {
      final source = _read(
        'lib/features/qr/screens/transfer_carnets_screen.dart',
      );

      expect(source, contains('bool _submitting = false;'));
      expect(source, isNot(contains('final bool _submitting = false;')));
      expect(source, contains('if (_submitting) return;'));
      expect(source, contains('setState(() => _submitting = true);'));
      expect(source, contains('setState(() => _submitting = false);'));
      expect(source, contains('onSubmit: _submitting ? null : _submit'));
      expect(source, contains('unconfirmedActionMessage'));
      expect(source, contains('l10n.transferUnconfirmedCarnets'));
    });

    test('ticket transfer parent has a real mutable submit lock', () {
      final source = _read(
        'lib/features/qr/screens/transfer_tickets_screen.dart',
      );

      expect(source, contains('bool _submitting = false;'));
      expect(source, isNot(contains('final bool _submitting = false;')));
      expect(source, contains('if (_submitting) return;'));
      expect(source, contains('setState(() => _submitting = true);'));
      expect(source, contains('setState(() => _submitting = false);'));
      expect(source, contains('onSubmit: _submitting ? null : _submit'));
      expect(source, contains('unconfirmedActionMessage'));
      expect(source, contains('l10n.transferUnconfirmedTickets'));
    });

    test(
      'confirmation locks before PIN dialog to prevent double confirmation',
      () {
        final source = _read(
          'lib/features/qr/screens/transfer_confirmation_screen.dart',
        );

        final lockIndex = source.indexOf('setState(() => _confirming = true);');
        final pinIndex = source.indexOf('showSensitiveActionCodeDialog');
        expect(lockIndex, greaterThanOrEqualTo(0));
        expect(pinIndex, greaterThanOrEqualTo(0));
        expect(lockIndex, lessThan(pinIndex));

        expect(source, contains('unconfirmedActionMessage'));
        expect(source, contains('ErrorPresenter.isBackendUnavailable(e)'));
        expect(source, contains('widget.args.unconfirmedActionMessage'));
        expect(
          source,
          isNot(
            contains(
              "e.isOdooSessionExpired || e.isAuthRequired\n"
              "              ? 'Session expirée. Reconnectez-vous.'\n"
              "              : e.message",
            ),
          ),
        );
      },
    );
  });
}

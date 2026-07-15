import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _classBlock(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0));
  final end = source.indexOf(endMarker, start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  group('Station manual QR success and failure dialog guard', () {
    test('manual QR success uses final dialog and returns to station home', () {
      final source = _read(
        'lib/features/station/screens/station_manual_qr_screen.dart',
      );
      final dialogSource = _read(
        'lib/shared/widgets/station_qr_success_dialog.dart',
      );

      expect(source, contains('final guarded = acpecRpcMapOrThrow('));
      expect(source, contains('StationQrSuccessDialog('));
      expect(dialogSource, contains('QR consommé avec succès'));
      expect(dialogSource, contains('Montant'));
      expect(dialogSource, contains('Date/heure'));
      expect(dialogSource, contains('N° transaction'));
      expect(source, contains('transaction_name'));
      expect(dialogSource, contains('Terminer'));
      expect(source, contains("context.go('/station/home')"));

      expect(source, isNot(contains("_showSnack('QR consommé avec succès.')")));
      expect(source, isNot(contains("context.go('/station/journal')")));
    });

    test(
      'manual QR failure uses blocking dialog and stays on manual entry',
      () {
        final source = _read(
          'lib/features/station/screens/station_manual_qr_screen.dart',
        );

        expect(source, contains('Future<void> _showManualFailureDialog'));
        expect(source, contains('Opération refusée'));
        expect(source, contains('Consommation non confirmée'));
        expect(source, contains('Retour à la saisie'));
        expect(source, contains('_sensitiveActionErrorMessage(e)'));
      },
    );

    test(
      'manual non consumable checked QR uses dialog, not red result card',
      () {
        final source = _read(
          'lib/features/station/screens/station_manual_qr_screen.dart',
        );

        expect(
          source,
          contains('final result = StationQrCheckResult.fromRpc(raw);'),
        );
        expect(source, contains('if (!result.canConsume)'));
        expect(source, contains("title: 'QR non consommable'"));
        expect(
          source,
          contains('Le serveur indique que ce QR n’est pas consommable.'),
        );
        expect(source, contains("actionLabel: 'Retour à l’accueil'"));
        expect(source, contains("context.go('/station/home')"));

        expect(source, contains('if (data != null && canConsume)'));

        final card = _classBlock(
          source,
          'class _CheckResultCard extends StatelessWidget',
          'class _InfoRow extends StatelessWidget',
        );

        expect(card, contains("const statusText = 'Consommable';"));
        expect(card, contains('AppColors.leaderGreen'));
        expect(card, isNot(contains('Non consommable')));
        expect(card, isNot(contains('canConsume')));
        expect(card, isNot(contains('Colors.red.shade700')));
        expect(card, isNot(contains("label: 'Motif'")));
      },
    );
  });
}

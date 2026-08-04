import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/core/utils/error_presenter.dart';
import 'package:fueltoken_app/data/services/odoo_jsonrpc_client.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

void main() {
  group('ErrorPresenter safe public messages', () {
    test('maps an invalid action code without exposing backend wording', () {
      final message = ErrorPresenter.message(
        OdooJsonRpcException(
          'psycopg2 traceback private_table',
          publicCode: 'INVALID_ACTION_CODE',
          reference: 'SEC-PIN-1',
        ),
      );

      expect(message, contains('PIN incorrect'));
      expect(message, contains('SEC-PIN-1'));
      expect(message, isNot(contains('psycopg2')));
      expect(message, isNot(contains('private_table')));
    });

    test('hides an unknown Odoo technical message', () {
      final message = ErrorPresenter.message(
        OdooJsonRpcException(
          'KeyError res.users secret_field',
          code: -32603,
          reference: 'ERR-RPC-1',
        ),
      );

      expect(message, contains('Une erreur est survenue'));
      expect(message, contains('ERR-RPC-1'));
      expect(message, isNot(contains('KeyError')));
      expect(message, isNot(contains('secret_field')));
    });

    test('rejects an invalid support reference', () {
      final message = ErrorPresenter.message(
        OdooJsonRpcException(
          'private backend wording',
          reference: '<script>alert(1)</script>',
        ),
      );

      expect(message, 'Une erreur est survenue. Réessayez.');
    });

    test('keeps safe local HTTP status messages', () {
      final message = ErrorPresenter.message(
        OdooJsonRpcException(
          'Vous n’êtes pas autorisé à effectuer cette action.',
          code: 403,
        ),
      );

      expect(message, 'Vous n’êtes pas autorisé à effectuer cette action.');
    });
    testWidgets('localizes an invalid PIN in Arabic without backend wording', (
      tester,
    ) async {
      late String message;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              message = ErrorPresenter.localizedMessage(
                context,
                OdooJsonRpcException(
                  'private backend PIN failure',
                  publicCode: 'INVALID_ACTION_CODE',
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final context = tester.element(find.byType(SizedBox));
      expect(message, AppLocalizations.of(context).commonPinIncorrect);
      expect(message, isNot(contains('private backend')));
    });
  });
}

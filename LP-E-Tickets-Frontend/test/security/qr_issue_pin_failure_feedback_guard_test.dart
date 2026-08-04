import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2N QR issue PIN failure feedback guard', () {
    test('QR issue backend errors are not swallowed silently', () {
      final source = _read('lib/features/qr/screens/emit_qr_screen.dart');

      expect(source, contains('ErrorPresenter.isBackendUnavailable(error)'));
      expect(
        source,
        contains('ErrorPresenter.localizedMessage(context, error)'),
      );
      expect(source, contains('AppLocalizations.of(context).qrUnconfirmed'));
      expect(
        source,
        contains('AppMessage.error(context, _qrIssueErrorMessage(err))'),
      );
      expect(source, isNot(contains("lower.contains('action_code')")));

      expect(
        source,
        isNot(contains('} on OdooJsonRpcException {\n      return;')),
      );
      expect(source, isNot(contains('} catch (err) {\n      return;')));
    });

    test(
      'QR confirmation locks before PIN dialog to avoid duplicate dialogs',
      () {
        final source = _read(
          'lib/features/qr/screens/qr_action_confirmation_screen.dart',
        );

        final confirmIndex = source.indexOf('Future<void> _confirm()');
        final lockIndex = source.indexOf(
          'setState(() => _confirming = true);',
          confirmIndex,
        );
        final pinIndex = source.indexOf(
          'showSensitiveActionCodeDialog',
          confirmIndex,
        );

        expect(confirmIndex, greaterThanOrEqualTo(0));
        expect(lockIndex, greaterThanOrEqualTo(0));
        expect(pinIndex, greaterThanOrEqualTo(0));
        expect(lockIndex, lessThan(pinIndex));
      },
    );

    test('QR issue success path still refreshes QR and read models', () {
      final source = _read('lib/features/qr/screens/emit_qr_screen.dart');

      expect(source, contains('_refreshClientReadModelsAfterQrIssue();'));
      expect(source, contains('QrRefreshBus.instance.bump();'));
      expect(source, contains('FacesRefreshBus.instance.bump();'));
      expect(source, contains('WalletRefreshBus.instance.bump();'));
      expect(source, contains('showQrGenerationSuccessDialog'));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2L3C purchase sensitive actions guard', () {
    test('purchase confirmation locks before PIN dialog', () {
      final source = _read(
        'lib/features/purchases/screens/purchase_confirmation_screen.dart',
      );

      final confirmIndex = source.indexOf('Future<void> _onConfirm()');
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
      expect(source, contains('unconfirmedActionMessage'));
      expect(source, contains('ErrorPresenter.isBackendUnavailable(e)'));
      expect(source, contains('widget.args.unconfirmedActionMessage'));
      expect(source, isNot(contains('on OdooJsonRpcException catch')));
    });

    test(
      'purchase submit parent already has submit lock and idempotency key',
      () {
        final source = _read(
          'lib/features/purchases/screens/submit_purchase_screen.dart',
        );

        expect(source, contains('bool _submitting = false;'));
        expect(source, contains('if (_submitting) return;'));
        expect(source, contains('setState(() => _submitting = true);'));
        expect(source, contains('setState(() => _submitting = false);'));
        expect(source, contains("'idempotency_key': idem"));
        expect(source, contains('purchasesCreate'));
      },
    );

    test('purchase approval locks before PIN dialog', () {
      final source = _read(
        'lib/features/purchases/screens/purchase_detail_screen.dart',
      );

      final approveIndex = source.indexOf('Future<void> _confirmApprove()');
      final lockIndex = source.indexOf(
        'setState(() => _approving = true);',
        approveIndex,
      );
      final pinIndex = source.indexOf(
        'showSensitiveActionCodeDialog',
        approveIndex,
      );

      expect(approveIndex, greaterThanOrEqualTo(0));
      expect(lockIndex, greaterThanOrEqualTo(0));
      expect(pinIndex, greaterThanOrEqualTo(0));
      expect(lockIndex, lessThan(pinIndex));
      expect(source, contains('if (_approving) return;'));
      expect(source, contains("'idempotency_key': const Uuid().v4()"));
    });

    test('purchase approval uses prudent backend unavailable message', () {
      final source = _read(
        'lib/features/purchases/screens/purchase_detail_screen.dart',
      );

      expect(source, contains('_unconfirmedPurchaseActionMessage'));
      expect(
        source,
        contains('Vérifiez l’état de la demande avant de réessayer'),
      );
      expect(source, contains('ErrorPresenter.isBackendUnavailable(e)'));
      expect(source, contains('ErrorPresenter.message(e)'));
      expect(
        source,
        isNot(
          contains(
            "return e.toString().replaceFirst('Exception: ', '').trim();",
          ),
        ),
      );
    });
  });
}

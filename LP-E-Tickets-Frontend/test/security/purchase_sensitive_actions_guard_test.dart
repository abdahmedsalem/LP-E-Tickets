import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('purchase retries retain their identity throughout confirmation', () {
    final source = _read(
      'lib/features/purchases/screens/submit_purchase_screen.dart',
    );
    final callback = source.indexOf('onConfirm: (actionCode)');
    final identity = source.indexOf('final idem =');
    final reference = source.indexOf('final payRef =');
    expect(identity, greaterThanOrEqualTo(0));
    expect(reference, greaterThanOrEqualTo(0));
    expect(identity, lessThan(callback));
    expect(reference, lessThan(callback));
    expect(source.substring(callback), isNot(contains('Uuid().v4()')));
  });
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
  });
}

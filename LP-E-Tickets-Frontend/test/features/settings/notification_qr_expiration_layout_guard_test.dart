import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR expiration details do not render a QR preview block', () {
    final source = File(
      'lib/features/settings/screens/notifications_screen.dart',
    ).readAsStringSync();
    final tile = source.substring(source.indexOf('class _QrExpirationTile'));

    expect(tile, isNot(contains('MiniQR(')));
    expect(tile, isNot(contains('QrState.expired')));
    expect(tile, contains('l10n.amount'));
    expect(tile, contains('l10n.notificationsViewQr'));
  });
}

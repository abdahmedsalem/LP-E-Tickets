import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('transfer screens show instructions only when data is available', () {
    final carnets = _read(
      'lib/features/qr/screens/transfer_carnets_screen.dart',
    );
    final tickets = _read(
      'lib/features/qr/screens/transfer_tickets_screen.dart',
    );

    expect(carnets, contains('if (transferable.isNotEmpty) ...['));
    expect(tickets, contains('if (transferable.isNotEmpty) ...['));
    expect(carnets, isNot(contains('Seuls les carnets complets')));
    expect(tickets, isNot(contains('Seuls les tickets disponibles')));
  });

  test('purchase screen shows instructions only after offers load', () {
    final source = _read(
      'lib/features/purchases/screens/submit_purchase_screen.dart',
    );

    expect(
      source,
      contains(
        'if (!_loadingOffers &&\n'
        '                      _offerLoadError == null &&\n'
        '                      _offerTypes.isNotEmpty) ...[',
      ),
    );
    expect(source, contains('bottomNavigationBar: _offerTypes.isEmpty'));
  });

  test('QR generation shows instructions only with loaded carnet cards', () {
    final source = _read('lib/features/qr/screens/emit_qr_screen.dart');

    expect(source, isNot(contains('l10n.qrGenerationSelectInstruction')));
    expect(source, contains('final hasEntries = availableLines.isNotEmpty'));
    expect(source, contains('l10n.qrGenerationChooseInstruction'));
  });

  test('all four screens use the shared empty state component', () {
    final paths = <String>[
      'lib/features/qr/screens/emit_qr_screen.dart',
      'lib/features/qr/screens/transfer_carnets_screen.dart',
      'lib/features/qr/screens/transfer_tickets_screen.dart',
      'lib/features/purchases/screens/submit_purchase_screen.dart',
    ];

    for (final path in paths) {
      expect(_read(path), contains('EmptyState('), reason: path);
    }

    expect(
      _read('lib/features/qr/screens/emit_qr_screen.dart'),
      isNot(contains('class _EmptyAvailable')),
    );

    final sharedEmptyState = _read('lib/shared/widgets/empty_state.dart');
    expect(sharedEmptyState, contains('_EmptyFolderPainter'));
    expect(sharedEmptyState, contains('color: AppColors.leaderGreen'));
    expect(sharedEmptyState, contains("final displayText ="));
    expect(sharedEmptyState, isNot(contains('shape: BoxShape.circle')));
  });
}

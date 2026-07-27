import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('station history restores the summary statistics above cards', () {
    final source = File(
      'lib/features/station/screens/station_consumption_history_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class _StationHistoryTotalsCard'));
    expect(source, contains('class _StationHistoryTotalTile'));
    expect(source, contains('l10n.stationHistorySummary'));
    expect(source, contains('l10n.stationConsumedQr'));
    expect(source, contains('l10n.stationTotal'));
    expect(source, contains('qrCount: shown.length'));
    final tileStart = source.indexOf(
      'class _StationHistoryTotalTile extends StatelessWidget',
    );
    final tileEnd = source.indexOf(
      'class _StationHistoryRow extends StatefulWidget',
      tileStart,
    );
    final tileSource = source.substring(tileStart, tileEnd);
    expect(tileSource, contains('width: double.infinity'));
    expect(tileSource, contains('textAlign: TextAlign.center'));
  });

  test('station history cards preserve the bd3ac4f6 expandable layout', () {
    final source = File(
      'lib/features/station/screens/station_consumption_history_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class _StationHistoryRow extends StatefulWidget'));
    expect(source, contains('bool _expanded = false;'));
    expect(source, contains('stationFuelConsumption'));
    expect(source, contains('alignment: AlignmentDirectional.centerStart'));
    expect(source, contains('AnimatedRotation('));
    expect(source, contains('AnimatedSize('));
    expect(source, contains('_StationConsumptionPanel(transaction: tx)'));
    expect(
      source,
      contains('(label: l10n.stationTransactionNumber, value: tx.txNumber)'),
    );
    expect(source, contains('(label: l10n.stationClient, value: clientLabel)'));
    expect(source, contains('(label: l10n.station, value: stationLabel)'));
    expect(source, contains('(label: l10n.stationQrCode, value: titleCode)'));
  });
}

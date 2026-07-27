import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('station result dialogs use one branded popup frame', () {
    final frame = _read('lib/shared/widgets/station_popup_frame.dart');
    final success = _read('lib/shared/widgets/station_qr_success_dialog.dart');
    final failure = _read('lib/shared/widgets/station_qr_failure_dialog.dart');

    expect(success, contains('StationPopupFrame('));
    expect(failure, contains('StationPopupFrame('));
    expect(frame, contains('BorderRadius.circular(28)'));
    expect(frame, contains('Border.all(color: AppColors.line)'));
    expect(frame, contains('FilledButton('));
    expect(success, contains('AppColors.validGradient'));
    expect(failure, contains('AppColors.danger'));
  });

  test('station success uses the client operation summary component', () {
    final stationSuccess = _read(
      'lib/shared/widgets/station_qr_success_dialog.dart',
    );
    final clientSuccess = _read(
      'lib/shared/widgets/purchase_submit_success_dialog.dart',
    );
    final summary = _read(
      'lib/shared/widgets/operation_success_summary_card.dart',
    );

    expect(stationSuccess, contains('OperationSuccessSummaryCard('));
    expect(clientSuccess, contains('OperationSuccessSummaryCard(rows: rows)'));
    expect(summary, contains('padding: const EdgeInsets.all(18)'));
    expect(summary, contains('BorderRadius.circular(20)'));
    expect(summary, contains('const SizedBox(height: 12)'));
  });

  test('station QR and language sheets use the branded visual tokens', () {
    final scan = _read('lib/features/station/screens/scan_screen.dart');
    final profile = _read(
      'lib/features/station/screens/station_profile_screen.dart',
    );

    expect(scan, contains('class _StationQrCheckSheet'));
    expect(scan, contains('gradient: AppColors.validGradient'));
    expect(scan, contains('backgroundColor: AppColors.leaderGreen'));
    expect(scan, contains('barrierColor: AppColors.ink'));
    expect(profile, contains('class _StationLanguageSheet'));
    expect(profile, contains('class _StationLanguageOption'));
    expect(profile, contains('gradient: AppColors.validGradient'));
    expect(profile, contains('AppColors.successSurface'));
  });
}

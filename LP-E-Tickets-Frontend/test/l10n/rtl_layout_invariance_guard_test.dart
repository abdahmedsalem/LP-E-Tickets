import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

Iterable<File> _applicationDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (file) =>
          file.path.endsWith('.dart') &&
          !file.path.contains(
            '${Platform.pathSeparator}l10n${Platform.pathSeparator}app_localizations',
          ),
    );

void main() {
  test('Arabic locale does not conditionally change screen geometry', () {
    final localeGeometry = RegExp(
      r"languageCode\s*==\s*'ar'\s*\?\s*(?:const\s+)?"
      r'(?:EdgeInsets|SizedBox|Alignment|TextStyle|FontWeight|[0-9])',
      multiLine: true,
    );

    for (final file in _applicationDartFiles()) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(matches(localeGeometry)),
        reason: '${file.path} must keep identical geometry in fr and ar',
      );
    }
  });

  test('locale never selects a different font or text size', () {
    final localeTypography = RegExp(
      r"languageCode\s*(?:==|!=)\s*'ar'[\s\S]{0,100}"
      r'(?:fontFamily|fontSize|FontWeight|AppTypography\.arabic)',
      multiLine: true,
    );

    for (final file in _applicationDartFiles()) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(matches(localeTypography)),
        reason: '${file.path} must share typography between fr and ar',
      );
    }

    final themes =
        '${_read('lib/core/theme/app_theme.dart')}\n'
        '${_read('lib/core/theme/app_typography.dart')}';
    expect(themes, isNot(contains('Localizations.localeOf')));
    expect(themes, isNot(contains('languageCode')));
  });

  test('localized UI uses logical start and end alignment everywhere', () {
    final physicalAlignment = RegExp(
      r'TextAlign\.(?:left|right)|'
      r'EdgeInsets\.only\([^\n]*(?:left|right)|'
      r'Alignment\.(?:centerLeft|centerRight)',
    );

    for (final file in _applicationDartFiles()) {
      final source = file.readAsStringSync();
      final matches = physicalAlignment.allMatches(source).toList();
      if (file.path.endsWith('fuel_brand_lottie.dart')) {
        expect(matches.length, 2, reason: file.path);
        continue;
      }
      expect(matches, isEmpty, reason: file.path);
    }
  });

  test('splash keeps the same widget structure in French and Arabic', () {
    final source = _read('lib/features/auth/screens/splash_screen.dart');

    expect(
      source,
      matches(
        RegExp(r'if \(AppBrandConfig\s*\.operatorTagline\s*\.isNotEmpty\)'),
      ),
    );
    expect(source, isNot(contains('Localizations.localeOf(context)')));
  });

  test(
    'localized layouts use directional positioning without size changes',
    () {
      final expectations = <String, String>{
        'lib/shared/widgets/overview_info_card.dart':
            'textAlign: TextAlign.end',
        'lib/shared/widgets/amount_inline.dart':
            'this.textAlign = TextAlign.start',
        'lib/shared/widgets/wallet_card.dart':
            'AlignmentDirectional.centerStart',
        'lib/shared/widgets/auth_action_code_dialog.dart':
            'AlignmentDirectional.centerStart',
        'lib/features/home/screens/user_home_screen.dart':
            'EdgeInsetsDirectional.only(start: 6)',
        'lib/features/settings/screens/notifications_screen.dart':
            'textAlign: TextAlign.end',
        'lib/features/purchases/screens/submit_purchase_screen.dart':
            'EdgeInsetsDirectional.only(end: 112)',
        'lib/features/transactions/screens/transactions_screen.dart':
            'this.textAlign = TextAlign.start',
        'lib/features/qr/screens/transfer_confirmation_screen.dart':
            'this.textAlign = TextAlign.start',
        'lib/shared/widgets/fuel_brand_lottie.dart':
            'EdgeInsetsDirectional.fromSTEB(16, 12, 64, 12)',
        'lib/shared/widgets/backend_unavailable_banner.dart':
            'EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12)',
        'lib/shared/widgets/list_filters_sheet.dart':
            'EdgeInsetsDirectional.fromSTEB(20, 14, 12, 8)',
        'lib/shared/widgets/loading_skeleton.dart':
            'EdgeInsetsDirectional.fromSTEB(10, 14, 4, 14)',
        'lib/features/qr/screens/qr_list_screen.dart':
            'EdgeInsetsDirectional.fromSTEB(14, 14, 12, 14)',
        'lib/features/station/screens/scan_screen.dart':
            'EdgeInsetsDirectional.fromSTEB(14, 12, 26, 0)',
      };

      for (final entry in expectations.entries) {
        expect(_read(entry.key), contains(entry.value), reason: entry.key);
      }
    },
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('language selection follows authentication visual identity', () {
    final source = File(
      'lib/features/auth/screens/language_selection_screen.dart',
    ).readAsStringSync();

    expect(source, contains('FuelLogo('));
    expect(source, contains('AppColors.loginHeroGradient'));
    expect(source, contains('Radius.circular(28)'));
    expect(source, contains('AppColors.elevatedShadow'));
    expect(source, contains('Icons.translate_rounded'));
    expect(source, contains('height: 56'));
    expect(source, contains('backgroundColor: AppColors.leaderGreen'));
  });

  test('language cards remain accessible and RTL aware', () {
    final source = File(
      'lib/features/auth/screens/language_selection_screen.dart',
    ).readAsStringSync();

    expect(source, contains('Semantics('));
    expect(source, contains('selected: selected'));
    expect(source, contains('AlignmentDirectional.centerStart'));
    expect(source, isNot(contains('TextAlign.left')));
    expect(source, isNot(contains('TextAlign.right')));
    expect(source, isNot(contains('Alignment.centerLeft')));
    expect(source, isNot(contains('Alignment.centerRight')));
  });
}

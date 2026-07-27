import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app hides only the top status bar at startup and resume', () {
    final source = File('lib/main.dart').readAsStringSync();
    final helperStart = source.indexOf('Future<void> _hideStatusBar()');
    final mainStart = source.indexOf('void main() async');
    final helper = source.substring(helperStart, mainStart);

    expect(helperStart, greaterThanOrEqualTo(0));
    expect(helper, contains('SystemUiMode.manual'));
    expect(helper, contains('overlays: const [SystemUiOverlay.bottom]'));
    expect(helper, isNot(contains('SystemUiOverlay.top')));
    expect(source, contains('await _hideStatusBar();'));
    expect(source, contains('unawaited(_hideStatusBar());'));
  });
}

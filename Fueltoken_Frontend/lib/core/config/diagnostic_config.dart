import 'package:flutter/foundation.dart';

/// Logs détaillés (JSON-RPC, presse-papiers technique) : désactivés en release.
///
/// Pour le support sur un build release : `--dart-define=FUELTOKEN_VERBOSE_DIAGNOSTIC=true`
class DiagnosticConfig {
  DiagnosticConfig._();

  static const bool verboseFromDefine = bool.fromEnvironment(
    'FUELTOKEN_VERBOSE_DIAGNOSTIC',
    defaultValue: false,
  );

  /// `true` uniquement en `flutter run` debug, ou si le define est activé (support).
  static bool get showTechnicalDiagnostics => kDebugMode || verboseFromDefine;
}

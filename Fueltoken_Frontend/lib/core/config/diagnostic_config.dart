import 'package:flutter/foundation.dart';

/// Logs détaillés (JSON-RPC, presse-papiers technique) : désactivés en release.
///
/// En release, `FUELTOKEN_VERBOSE_DIAGNOSTIC=true` seul ne suffit pas.
/// Il faut aussi `ALLOW_VERBOSE_DIAGNOSTIC_IN_RELEASE=true`, réservé au support.
class DiagnosticConfig {
  DiagnosticConfig._();

  static const bool verboseFromDefine = bool.fromEnvironment(
    'FUELTOKEN_VERBOSE_DIAGNOSTIC',
    defaultValue: false,
  );

  static const bool rpcDebugFromDefine = bool.fromEnvironment(
    'ODOO_DEBUG_RPC',
    defaultValue: false,
  );

  static const bool allowVerboseDiagnosticsInRelease = bool.fromEnvironment(
    'ALLOW_VERBOSE_DIAGNOSTIC_IN_RELEASE',
    defaultValue: false,
  );

  static bool get _releaseDiagnosticsAllowed =>
      !kReleaseMode || allowVerboseDiagnosticsInRelease;

  /// Diagnostics techniques UI : debug local, ou support explicitement autorisé.
  static bool get showTechnicalDiagnostics =>
      kDebugMode || (verboseFromDefine && _releaseDiagnosticsAllowed);

  /// Logs JSON-RPC détaillés : jamais activables en release normale par accident.
  static bool get rpcDebugEnabled =>
      kDebugMode || (rpcDebugFromDefine && _releaseDiagnosticsAllowed);
}

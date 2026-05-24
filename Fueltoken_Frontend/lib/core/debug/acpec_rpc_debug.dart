import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Journaux de debug des requêtes JSON-RPC (activables en debug ou `ODOO_DEBUG_RPC=true`).
class AcpecRpcDebug {
  AcpecRpcDebug._();

  static const bool fromDefine = bool.fromEnvironment(
    'ODOO_DEBUG_RPC',
    defaultValue: false,
  );

  static bool get enabled => kDebugMode || fromDefine;

  static Map<String, dynamic> redactParams(Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) {
      return <String, dynamic>{};
    }
    return _redactMap(Map<String, dynamic>.from(params));
  }

  static Map<String, dynamic> _redactMap(Map<String, dynamic> m) {
    const sensitive = {
      'secret_code',
      'password',
      'proof_data',
      'token',
      'access',
      'refresh',
    };
    final o = <String, dynamic>{};
    for (final e in m.entries) {
      final lk = e.key.toLowerCase();
      if (sensitive.contains(lk)) {
        final s = e.value?.toString() ?? '';
        o[e.key] = s.isEmpty ? '(empty)' : '*** len=${s.length}';
      } else if (e.value is Map) {
        o[e.key] = _redactMap(Map<String, dynamic>.from(e.value as Map));
      } else {
        o[e.key] = e.value;
      }
    }
    return o;
  }

  static String clip(dynamic data, [int max = 2600]) {
    String s;
    try {
      if (data is Map || data is List) {
        const enc = JsonEncoder.withIndent('  ');
        s = enc.convert(data);
      } else {
        s = data?.toString() ?? '';
      }
    } catch (_) {
      s = data?.toString() ?? '';
    }
    if (s.length <= max) return s;
    return '${s.substring(0, max)}\n… [+${s.length - max} chars]';
  }

  /// One block per RPC: URL, envelope (method **call**), redacted params, headers, HTTP + body.
  static void logRoundTrip({
    required String httpPath,
    required String fullUrl,
    required Map<String, dynamic> jsonRpcEnvelope,
    bool cookiePresent = false,
    String? xOdooDatabase,
    int? httpStatus,
    dynamic responseBody,
    String? note,
  }) {
    if (!enabled) return;
    // Une seule ligne montrant l’URL réelle POST (les lignes flutter: ne font pas partie du corps HTTP).
    debugPrint('POST $fullUrl');
    final params = jsonRpcEnvelope['params'];
    final paramsMap = params is Map
        ? Map<String, dynamic>.from(params)
        : <String, dynamic>{};
    final buf = StringBuffer()
      ..writeln('── ACPEC-RPC ───────────────────────────────')
      ..writeln('path : $httpPath')
      ..writeln('POST : $fullUrl')
      ..writeln(
        'JSON : jsonrpc=${jsonRpcEnvelope['jsonrpc']} method=${jsonRpcEnvelope['method']} id=${jsonRpcEnvelope['id']}',
      )
      ..writeln('params (sanitized): ${jsonEncode(redactParams(paramsMap))}')
      ..writeln('Cookie: ${cookiePresent ? 'yes (hidden)' : 'no'}')
      ..writeln(
        'X-Odoo-Database: ${(xOdooDatabase != null && xOdooDatabase.isNotEmpty) ? xOdooDatabase : '(not set — only if server requires it)'}',
      );
    if (note != null) {
      buf.writeln('note: $note');
    }
    if (httpStatus != null) {
      buf.writeln('HTTP: $httpStatus');
    }
    if (responseBody != null) {
      buf.writeln('body: ${clip(responseBody)}');
    }
    buf.writeln('────────────────────────────────────────────');
    developer.log(buf.toString(), name: 'ACPEC_RPC');
  }
}

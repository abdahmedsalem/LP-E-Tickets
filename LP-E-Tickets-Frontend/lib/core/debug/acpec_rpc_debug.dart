import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../config/diagnostic_config.dart';

/// Journaux de debug des requêtes JSON-RPC.
///
/// En release normale, `ODOO_DEBUG_RPC=true` seul ne suffit pas :
/// `ALLOW_VERBOSE_DIAGNOSTIC_IN_RELEASE=true` doit aussi être défini.
class AcpecRpcDebug {
  AcpecRpcDebug._();

  static bool get enabled => DiagnosticConfig.rpcDebugEnabled;

  static Map<String, dynamic> redactParams(Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) {
      return <String, dynamic>{};
    }
    final redacted = redactData(params);
    return redacted is Map<String, dynamic> ? redacted : <String, dynamic>{};
  }

  static Object? redactData(Object? value) => _redactValue(value);

  static Object? _redactValue(Object? value, [String? key]) {
    if (key != null && _isSensitiveKey(key)) {
      return _redactedValue(value);
    }
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final entryKey = entry.key.toString();
        out[entryKey] = _redactValue(entry.value, entryKey);
      }
      return out;
    }
    if (value is List) {
      return value.map(_redactValue).toList(growable: false);
    }
    return value;
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toLowerCase();
    const exact = <String>{
      'actioncode',
      'secretcode',
      'password',
      'pin',
      'proofdata',
      'qrnumericcode',
      'publiccode',
      'idempotencykey',
      'sessionid',
      'access',
      'accesskey',
      'accesstoken',
      'refreshtoken',
      'refresh',
      'token',
      'authorization',
      'cookie',
      'setcookie',
      'xacpecsession',
    };
    if (exact.contains(normalized)) return true;
    return normalized.endsWith('token') ||
        normalized.endsWith('secret') ||
        normalized.endsWith('password') ||
        normalized.endsWith('authorization');
  }

  static String _redactedValue(Object? value) {
    final s = value?.toString() ?? '';
    return s.isEmpty ? '(empty)' : '*** len=${s.length}';
  }

  static String clip(dynamic data, [int max = 2600]) {
    String s;
    try {
      final sanitized = redactData(data);
      if (sanitized is Map || sanitized is List) {
        const enc = JsonEncoder.withIndent('  ');
        s = enc.convert(sanitized);
      } else {
        s = sanitized?.toString() ?? '';
      }
    } catch (_) {
      s = '[unprintable sanitized payload]';
    }
    if (s.length <= max) return s;
    return '${s.substring(0, max)}\n… [+${s.length - max} chars]';
  }

  /// One block per RPC: URL, envelope (method **call**), redacted params, headers, HTTP + sanitized body.
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
    if (kDebugMode) {
      debugPrint('POST $fullUrl');
    }
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
      buf.writeln('body (sanitized): ${clip(responseBody)}');
    }
    buf.writeln('────────────────────────────────────────────');
    developer.log(buf.toString(), name: 'ACPEC_RPC');
  }
}

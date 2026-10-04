import 'odoo_jsonrpc_client.dart';
import '../../../core/errors/public_error_messages.dart';

/// Public ACPEC mobile API error carried inside JSON-RPC `result`.
///
/// The backend can return HTTP 200 and JSON-RPC success while the business
/// result is refused:
///
/// ```json
/// {
///   "ok": false,
///   "success": false,
///   "error": {
///     "code": "RATE_LIMITED",
///     "message": "...",
///     "reference": "SEC-..."
///   }
/// }
/// ```
///
/// Flutter must never branch on, or display, the backend `message` directly.
/// It uses [code] for logic and a local UX mapping for the displayed text.
class AcpecPublicApiError {
  const AcpecPublicApiError({
    required this.code,
    this.reference,
    this.backendMessage,
    this.raw,
  });

  final String code;
  final String? reference;

  /// Captured only for diagnostics. Do not display this value directly.
  final String? backendMessage;
  final Object? raw;

  bool get hasKnownCode => PublicErrorMessages.containsCode(code);

  static String publicMessageForCode(String? rawCode) {
    return PublicErrorMessages.forCode(rawCode);
  }

  String get publicMessage => publicMessageForCode(code);

  String get displayMessage {
    final ref = normalizedReference;
    if (ref == null ||
        code == 'INVALID_ACTION_CODE' ||
        code == 'SECRET_CODE_INVALID') {
      return publicMessage;
    }
    return '$publicMessage\nRéférence support : $ref';
  }

  String? get normalizedReference {
    final ref = reference?.trim();
    if (ref == null || ref.isEmpty) return null;
    if (!_looksLikeSupportReference(ref)) return null;
    return ref;
  }

  OdooJsonRpcException toException() {
    return OdooJsonRpcException(
      displayMessage,
      publicCode: code,
      reference: normalizedReference,
      data: raw,
    );
  }

  static AcpecPublicApiError fromBusinessEnvelope(
    Map<String, dynamic> envelope,
  ) {
    final candidate = _extractErrorMap(envelope);
    final code = _normalizeCode(
      candidate?['code'] ?? envelope['error_code'] ?? envelope['code'],
    );
    final reference = _normalizeReference(
      candidate?['reference'] ??
          candidate?['ref'] ??
          envelope['reference'] ??
          envelope['ref'],
    );
    final backendMessage = _safeText(
      candidate?['message'] ??
          candidate?['detail'] ??
          candidate?['reason'] ??
          envelope['message'] ??
          envelope['detail'] ??
          envelope['reason'],
    );
    return AcpecPublicApiError(
      code: code,
      reference: reference,
      backendMessage: backendMessage,
      raw: envelope,
    );
  }

  static bool hasBusinessError(Map<String, dynamic> envelope) {
    bool isFalseValue(dynamic v) {
      if (v == false || v == 0) return true;
      if (v is String) {
        final s = v.trim().toLowerCase();
        return s == 'false' || s == '0' || s == 'no';
      }
      return false;
    }

    final status = envelope['status']?.toString().trim().toLowerCase();
    final code = envelope['code']?.toString().trim().toLowerCase();
    final error = envelope['error'];

    return isFalseValue(envelope['ok']) ||
        isFalseValue(envelope['success']) ||
        status == 'error' ||
        status == 'failed' ||
        status == 'failure' ||
        status == 'denied' ||
        status == 'rejected' ||
        code == 'error' ||
        code == 'failed' ||
        code == 'access_denied' ||
        (error != null && error != false && error.toString().trim().isNotEmpty);
  }

  static Map<String, dynamic>? _extractErrorMap(Map<String, dynamic> envelope) {
    final error = envelope['error'];
    if (error is Map) return Map<String, dynamic>.from(error);
    final data = envelope['data'];
    if (data is Map) {
      final dataMap = Map<String, dynamic>.from(data);
      final dataError = dataMap['error'];
      if (dataError is Map) return Map<String, dynamic>.from(dataError);
    }
    return null;
  }

  static String _normalizeCode(dynamic value) {
    final raw = _safeText(value);
    if (raw == null) return 'REQUEST_REFUSED';
    final code = raw.trim().toUpperCase().replaceAll('-', '_');
    if (code.isEmpty || code == 'FALSE' || code == 'NULL') {
      return 'REQUEST_REFUSED';
    }
    return code;
  }

  static String? _normalizeReference(dynamic value) {
    final ref = _safeText(value);
    if (ref == null || !_looksLikeSupportReference(ref)) return null;
    return ref;
  }

  static String? _safeText(dynamic value) {
    if (value == null || value == false) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower == 'false' || lower == 'null') return null;
    return s;
  }

  static bool _looksLikeSupportReference(String value) {
    return RegExp(r'^(SEC|ERR)-[A-Za-z0-9_.:/-]+$').hasMatch(value.trim());
  }
}

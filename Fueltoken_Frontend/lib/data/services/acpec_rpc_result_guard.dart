import 'odoo_jsonrpc_client.dart';

Map<String, dynamic> acpecRpcMapOrThrow(
  dynamic raw, {
  required String fallbackMessage,
  String? publicErrorMessage,
}) {
  final root = _asMap(raw, fallbackMessage);
  _throwIfBusinessError(
    root,
    fallbackMessage,
    publicErrorMessage: publicErrorMessage,
  );

  final data = root['data'];
  if (data is Map) {
    final dataMap = Map<String, dynamic>.from(data);
    _throwIfBusinessError(
      dataMap,
      fallbackMessage,
      publicErrorMessage: publicErrorMessage,
    );
    return dataMap;
  }

  return root;
}

Map<String, dynamic> _asMap(dynamic raw, String fallbackMessage) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw OdooJsonRpcException(fallbackMessage);
}

void _throwIfBusinessError(
  Map<String, dynamic> m,
  String fallbackMessage, {
  String? publicErrorMessage,
}) {
  bool isFalseValue(dynamic v) {
    if (v == false || v == 0) return true;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'false' || s == '0' || s == 'no';
    }
    return false;
  }

  final status = m['status']?.toString().trim().toLowerCase();
  final code = m['code']?.toString().trim().toLowerCase();

  final hasBusinessError =
      isFalseValue(m['success']) ||
      isFalseValue(m['ok']) ||
      status == 'error' ||
      status == 'failed' ||
      status == 'failure' ||
      status == 'denied' ||
      status == 'rejected' ||
      code == 'error' ||
      code == 'failed' ||
      code == 'access_denied' ||
      m['error'] != null;

  if (!hasBusinessError) return;

  throw OdooJsonRpcException(
    publicErrorMessage ?? _extractMessage(m, fallbackMessage),
    data: m,
  );
}

String _extractMessage(Map<String, dynamic> m, String fallbackMessage) {
  for (final key in const [
    'message',
    'human_message',
    'user_message',
    'detail',
    'reason',
  ]) {
    final value = m[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'false') {
      return value;
    }
  }

  final err = m['error'];
  if (err is Map) {
    for (final key in const ['message', 'data', 'detail', 'reason']) {
      final value = err[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'false') {
        return value;
      }
    }
  } else if (err != null) {
    final value = err.toString().trim();
    if (value.isNotEmpty && value != 'false') return value;
  }

  return fallbackMessage;
}

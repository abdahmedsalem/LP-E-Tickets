import 'acpec_public_api_error.dart';
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
  if (!AcpecPublicApiError.hasBusinessError(m)) return;

  final publicError = AcpecPublicApiError.fromBusinessEnvelope(m);
  if (publicError.hasKnownCode) {
    throw publicError.toException();
  }

  final preferredMessage = publicErrorMessage?.trim();
  if (preferredMessage == null || preferredMessage.isEmpty) {
    if (fallbackMessage.trim().isNotEmpty) {
      throw OdooJsonRpcException(
        _withReference(fallbackMessage.trim(), publicError.normalizedReference),
        publicCode: publicError.code,
        reference: publicError.normalizedReference,
        data: m,
      );
    }
    throw publicError.toException();
  }

  throw OdooJsonRpcException(
    _withReference(preferredMessage, publicError.normalizedReference),
    publicCode: publicError.code,
    reference: publicError.normalizedReference,
    data: m,
  );
}

String _withReference(String message, String? reference) {
  final ref = reference?.trim();
  if (ref == null || ref.isEmpty || message.contains(ref)) return message;
  return '$message\nRéférence support : $ref';
}

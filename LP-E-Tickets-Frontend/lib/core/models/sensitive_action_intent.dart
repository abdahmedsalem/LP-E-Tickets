import 'package:uuid/uuid.dart';

/// Identifies one user intent for a sensitive FuelToken action.
///
/// The idempotency key stays stable while the same action is retried.
class SensitiveActionIntent {
  SensitiveActionIntent._({
    required this.operation,
    required this.idempotencyKey,
  });

  final String operation;
  final String idempotencyKey;

  factory SensitiveActionIntent.create(String operation) {
    final normalized = _normalizeOperation(operation);
    return SensitiveActionIntent._(
      operation: normalized,
      idempotencyKey: 'ft-$normalized-${const Uuid().v4()}',
    );
  }

  Map<String, dynamic> authParams(String actionCode) {
    final code = actionCode.trim();
    return <String, dynamic>{
      'action_code': code,
      'idempotency_key': idempotencyKey,
    };
  }

  Map<String, dynamic> withAuthParams(
    Map<String, dynamic> params, {
    required String actionCode,
  }) => <String, dynamic>{...params, ...authParams(actionCode)};

  static String _normalizeOperation(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    final cleaned = normalized.replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'sensitive-action' : cleaned;
  }
}

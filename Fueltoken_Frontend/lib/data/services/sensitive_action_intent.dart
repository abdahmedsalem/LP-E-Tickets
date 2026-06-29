import 'package:uuid/uuid.dart';

/// Intention utilisateur pour une action sensible FuelToken.
///
/// La clé d'idempotence est créée une seule fois pour l'intention et doit être
/// réutilisée pour tous les retries réseau de cette même intention.
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
  }) {
    return <String, dynamic>{
      ...params,
      ...authParams(actionCode),
    };
  }

  static String _normalizeOperation(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    final cleaned = normalized.replaceAll(RegExp(r'^-+|-+$'), '');
    if (cleaned.isEmpty) return 'sensitive-action';
    return cleaned;
  }
}

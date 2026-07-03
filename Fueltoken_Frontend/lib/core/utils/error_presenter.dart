import '../../data/services/odoo_jsonrpc_client.dart';

/// Traduit toute exception en message court et convivial pour l'utilisateur.
///
/// Utilisation :
///   `ErrorPresenter.message(e)` → String affichable dans un SnackBar.
class ErrorPresenter {
  ErrorPresenter._();

  static String message(Object error) {
    if (error is OdooJsonRpcException) {
      if (error.requiresReLogin) {
        return 'Votre session a expiré. Veuillez vous reconnecter.';
      }
      if (isBackendUnavailable(error)) {
        return backendUnavailable();
      }
      return _withReference(_sanitize(error.message), error.reference);
    }
    final raw = error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('OdooJsonRpcException: ', '')
        .trim();
    return _sanitize(raw);
  }

  static String network() =>
      'Impossible de joindre le serveur. Vérifiez votre connexion.';

  static String backendUnavailable() =>
      'Serveur momentanément indisponible. Vérifiez votre connexion ou réessayez plus tard.';

  static String sessionExpired() =>
      'Votre session a expiré. Veuillez vous reconnecter.';

  static bool isBackendUnavailable(Object error) {
    if (error is OdooJsonRpcException) {
      if (error.requiresReLogin || error.requiresLogout) return false;
      final publicCode = error.publicCode?.trim().toUpperCase();
      if (publicCode == 'SERVER_ERROR') return true;
      return _looksLikeBackendUnavailable(error.message) ||
          _looksLikeBackendUnavailable(error.toString());
    }
    return _looksLikeBackendUnavailable(error.toString());
  }

  static bool _looksLikeBackendUnavailable(String raw) {
    final lower = raw.toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection timed out') ||
        lower.contains('timeout') ||
        lower.contains('dioexception') ||
        lower.contains('server_error') ||
        lower.contains('serveur') && lower.contains('indisponible');
  }

  static String _withReference(String message, String? reference) {
    final ref = reference?.trim();
    if (ref == null || ref.isEmpty) return message;
    if (message.contains(ref)) return message;
    return '$message\nRéférence support : $ref';
  }

  static String _sanitize(String raw) {
    var msg = raw.trim();
    if (msg.isEmpty) return 'Une erreur est survenue. Réessayez.';

    final lower = msg.toLowerCase();
    if (lower.contains('<html') ||
        lower.contains('<!doctype') ||
        lower.contains('unexpected character') && lower.contains('json') ||
        lower.contains('formatexception') ||
        lower.contains('html') && lower.contains('json')) {
      return 'Le serveur a renvoyé une réponse invalide. Réessayez.';
    }
    if (lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable')) {
      return network();
    }

    msg = msg
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (msg.isEmpty) return 'Une erreur est survenue. Réessayez.';
    if (msg.length > 200) return '${msg.substring(0, 200)}…';
    return msg;
  }
}

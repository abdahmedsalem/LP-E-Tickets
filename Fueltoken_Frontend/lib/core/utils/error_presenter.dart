import '../../../data/services/odoo_jsonrpc_client.dart';

/// Traduit toute exception en message court et convivial pour l'utilisateur.
///
/// Utilisation :
///   `ErrorPresenter.message(e)` → String affichable dans un SnackBar.
class ErrorPresenter {
  ErrorPresenter._();

  static String message(Object error) {
    if (error is OdooJsonRpcException) {
      if (error.isOdooSessionExpired) {
        return 'Votre session a expiré. Veuillez vous reconnecter.';
      }
      final msg = error.message.trim();
      if (msg.isEmpty) return 'Une erreur est survenue. Réessayez.';
      // Raccourcir les messages très longs (traces techniques)
      if (msg.length > 200) return '${msg.substring(0, 200)}…';
      return msg;
    }
    final raw = error.toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('OdooJsonRpcException: ', '')
        .trim();
    if (raw.isEmpty) return 'Une erreur inattendue est survenue.';
    if (raw.length > 200) return '${raw.substring(0, 200)}…';
    return raw;
  }

  static String network() =>
      'Impossible de joindre le serveur. Vérifiez votre connexion.';

  static String sessionExpired() =>
      'Votre session a expiré. Veuillez vous reconnecter.';
}

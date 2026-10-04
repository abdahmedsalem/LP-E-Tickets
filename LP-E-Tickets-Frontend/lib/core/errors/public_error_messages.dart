/// Local, safe user-facing messages for public backend error codes.
class PublicErrorMessages {
  PublicErrorMessages._();

  static const _messages = <String, String>{
    'AUTH_REFUSED':
        'Connexion impossible. Vérifiez le numéro ou le code SMS, puis réessayez. Vous pouvez aussi créer un compte.',
    'RATE_LIMITED': 'Trop de tentatives. Réessayez plus tard.',
    'DEVICE_NOT_ALLOWED':
        'Cet appareil n’est pas autorisé à utiliser Tickets Carburant.',
    'ACTION_REFUSED': 'Action refusée. Vérifiez votre code puis réessayez.',
    'INVALID_ACTION_CODE': 'Code PIN incorrect.',
    'ACTION_CODE_LOCKED': 'Trop de tentatives. Réessayez plus tard.',
    'PIN_RESET_REQUIRED': 'PIN à réinitialiser. Utilisez PIN oublié.',
    'MISSING_ACTION_CODE': 'PIN requis pour confirmer cette opération.',
    'INVALID_ACTION_CODE_KEY': 'Demande invalide. Veuillez réessayer.',
    'ACTION_IN_PROGRESS': 'Une confirmation est déjà en cours.',
    'DEVICE_PENDING_TRUST': 'Cet appareil est en attente de validation.',
    'DEVICE_BLOCKED': 'Cet appareil est bloqué. Contactez l’administrateur.',
    'PAYMENT_PROOF_INVALID':
        'Preuve de paiement invalide. Formats acceptés : JPG, PNG ou PDF, taille maximale 5 Mo.',
    'QR_NOT_USABLE': 'Ce QR ne peut pas être utilisé.',
    'TRANSFER_REFUSED': 'Le transfert a été refusé.',
    'REQUEST_REFUSED': 'Demande refusée. Réessayez ou contactez le support.',
    'FORBIDDEN': 'Vous n’avez pas l’autorisation d’effectuer cette action.',
    'SIGNUP_NOT_ALLOWED':
        'Inscription impossible avec ce numéro. Si vous avez déjà un compte, connectez-vous.',
    'VALIDATION_ERROR': 'Certaines informations sont invalides ou incomplètes.',
    'ACCESS_ERROR': 'Accès refusé.',
    'AUTH_REQUIRED': 'Votre session a expiré. Veuillez vous reconnecter.',
    'REFRESH_TOKEN_REQUIRED':
        'Votre session a expiré. Veuillez vous reconnecter.',
    'SERVER_ERROR': 'Erreur serveur. Réessayez plus tard.',
    'PASSWORD_LOGIN_DISABLED':
        'La connexion par PIN legacy est désactivée. Utilisez le flux SMS.',
    'NAME_REQUIRED': 'Le nom est obligatoire.',
    'SECRET_CODE_REQUIRED': 'Le PIN est obligatoire.',
    'SECRET_CODE_INVALID': 'Code PIN incorrect.',
    'PHONE_REQUIRED': 'Le numéro de téléphone est obligatoire.',
  };

  static String forCode(String? rawCode) {
    final code = (rawCode ?? '').trim().toUpperCase().replaceAll('-', '_');
    return _messages[code] ?? _messages['REQUEST_REFUSED']!;
  }

  static bool containsCode(String rawCode) =>
      _messages.containsKey(rawCode.trim().toUpperCase().replaceAll('-', '_'));
}

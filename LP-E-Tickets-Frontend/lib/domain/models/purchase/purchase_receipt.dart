/// Réponse métier après création d’un achat mobile.
class AcpecPurchaseCreateResult {
  const AcpecPurchaseCreateResult({
    required this.purchaseId,
    required this.publicCode,
    required this.state,
    this.operationReference,
    this.paymentReference,
    this.paymentMethodName,
    this.paymentMerchantCode,
  });

  final String purchaseId;
  final String publicCode;

  final String? operationReference;

  /// Ex. `submitted`, `draft` (brut serveur).
  final String state;

  /// Référence paiement envoyée dans la requête (affichage récap).
  final String? paymentReference;

  /// Valeurs du moyen de paiement figées dans l’achat côté Odoo.
  final String? paymentMethodName;
  final String? paymentMerchantCode;
}

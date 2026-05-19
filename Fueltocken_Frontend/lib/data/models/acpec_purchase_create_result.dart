/// Réponse métier après création d’un achat mobile.
class AcpecPurchaseCreateResult {
  const AcpecPurchaseCreateResult({
    required this.purchaseId,
    required this.publicCode,
    required this.state,
    this.paymentReference,
  });

  final String purchaseId;
  final String publicCode;

  /// Ex. `submitted`, `draft` (brut serveur).
  final String state;

  /// Référence paiement envoyée dans la requête (affichage récap).
  final String? paymentReference;
}

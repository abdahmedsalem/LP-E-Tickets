enum PurchaseLotState { draft, submitted, approved, rejected }

extension PurchaseLotStateX on PurchaseLotState {
  String get label {
    switch (this) {
      case PurchaseLotState.draft:
        return 'Brouillon';
      case PurchaseLotState.submitted:
        return 'Commande de carnets';
      case PurchaseLotState.approved:
        return 'Carnets achetés';
      case PurchaseLotState.rejected:
        return 'Commande de carnets rejetée';
    }
  }
}

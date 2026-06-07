import 'package:flutter/foundation.dart';

/// Signal global pour forcer le rafraîchissement de la liste des achats.
/// Bumped après : soumission, approbation, rejet d'un achat.
class PurchasesRefreshBus {
  PurchasesRefreshBus._();
  static final PurchasesRefreshBus instance = PurchasesRefreshBus._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void bump() => revision.value += 1;
}

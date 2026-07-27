import 'package:flutter/foundation.dart';

/// Signal global pour forcer le rafraîchissement des carnets/faces disponibles.
/// Bumped après : émission QR, transfert de carnets, approbation d'achat.
class FacesRefreshBus {
  FacesRefreshBus._();
  static final FacesRefreshBus instance = FacesRefreshBus._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void bump() => revision.value += 1;
}

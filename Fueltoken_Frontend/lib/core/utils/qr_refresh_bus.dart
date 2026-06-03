import 'package:flutter/foundation.dart';

/// Signal global pour forcer le rafraîchissement de la liste QR.
class QrRefreshBus {
  QrRefreshBus._();

  static final QrRefreshBus instance = QrRefreshBus._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void bump() {
    revision.value += 1;
  }
}

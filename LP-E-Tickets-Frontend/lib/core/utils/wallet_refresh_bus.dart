import 'package:flutter/foundation.dart';

/// Signal global pour forcer le rafraîchissement du solde wallet.
class WalletRefreshBus {
  WalletRefreshBus._();

  static final WalletRefreshBus instance = WalletRefreshBus._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void bump() {
    revision.value += 1;
  }
}

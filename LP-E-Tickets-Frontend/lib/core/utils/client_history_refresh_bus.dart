import 'package:flutter/foundation.dart';

/// Signal global pour forcer le rafraîchissement de l’historique client.
class ClientHistoryRefreshBus {
  ClientHistoryRefreshBus._();

  static final ClientHistoryRefreshBus instance = ClientHistoryRefreshBus._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void bump() {
    revision.value += 1;
  }
}

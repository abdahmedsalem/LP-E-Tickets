import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';

/// Notifications utilisateur — alimentées par l’API (liste vide tant que non branchée).
class NotificationsStore {
  NotificationsStore._();
  static final NotificationsStore instance = NotificationsStore._();

  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  List<NotificationItem> get items => const [];

  void markAllRead() {
    unreadCount.value = 0;
  }

  void initCounts() {
    unreadCount.value = 0;
  }

  void markRead(String id) {
    unreadCount.value = items.where((e) => !e.read).length;
  }
}

import 'package:flutter/foundation.dart';

import '../../domain/models/app_user.dart';
import '../../domain/models/notifications/notification_item.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../services/notification_services/notifications_store.dart';
import '../services/notification_services/purchase_validation_notification_service.dart';

class NotificationsRepository implements NotificationsRepositoryContract {
  NotificationsRepository({
    PurchaseValidationNotificationService? service,
    NotificationsStore? store,
  }) : _service = service ?? PurchaseValidationNotificationService.instance,
       _store = store ?? NotificationsStore.instance;

  final PurchaseValidationNotificationService _service;
  final NotificationsStore _store;

  @override
  Future<void> syncForUser(AppUser user) => _service.syncForUser(user);
  @override
  void addListener(VoidCallback listener) => _store.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => _store.removeListener(listener);
  @override
  Future<void> loadForUser(String userId) => _store.loadForUser(userId);
  @override
  Future<void> markAllRead() => _store.markAllRead();
  @override
  void initCounts() => _store.initCounts();
  @override
  Future<void> migrateLegacyContent() => _store.migrateLegacyContent();
  @override
  Future<void> clearAndReset() => _store.clearAndReset();
  @override
  Future<void> load() => _store.load();
  @override
  List<NotificationItem> get items => _store.items;
  @override
  NotificationItem displayItem(NotificationItem item) =>
      _store.displayItem(item);
  @override
  int get unreadCount => _store.unreadCount.value;
}

import '../models/app_user.dart';
import '../models/notifications/notification_item.dart';

abstract interface class NotificationsRepositoryContract {
  Future<void> syncForUser(AppUser user);
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
  Future<void> loadForUser(String userId);
  Future<void> markAllRead();
  void initCounts();
  Future<void> migrateLegacyContent();
  Future<void> clearAndReset();
  Future<void> load();
  List<NotificationItem> get items;
  NotificationItem displayItem(NotificationItem item);
  int get unreadCount;
}

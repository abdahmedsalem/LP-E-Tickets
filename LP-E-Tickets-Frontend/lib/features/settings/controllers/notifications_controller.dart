import '../../../core/controllers/flow_controller.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/notifications/notification_item.dart';
import '../../../domain/repositories/notifications_repository.dart';

class NotificationsController extends FlowController {
  NotificationsController({required NotificationsRepositoryContract repository})
    : _repository = repository {
    _repository.addListener(_notifyStoreChanged);
  }

  final NotificationsRepositoryContract _repository;
  bool _disposed = false;

  void _notifyStoreChanged() {
    if (!_disposed) notifyListeners();
  }

  List<NotificationItem> get items => _repository.items;
  int get unreadCount => _repository.unreadCount;
  NotificationItem displayItem(NotificationItem item) =>
      _repository.displayItem(item);

  Future<void> loadForUser(String userId) async {
    await _repository.loadForUser(userId);
    _repository.initCounts();
    await _repository.migrateLegacyContent();
  }

  Future<void> markAllRead() => _repository.markAllRead();

  Future<void> syncForUser(AppUser user) =>
      execute('syncForUser', () => _repository.syncForUser(user));

  @override
  void dispose() {
    _disposed = true;
    _repository.removeListener(_notifyStoreChanged);
    super.dispose();
  }
}

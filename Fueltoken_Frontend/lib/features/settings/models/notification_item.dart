class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timeLabel,
    this.actionLabel,
    this.actionRoute,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String timeLabel;
  final String? actionLabel;
  final String? actionRoute;
  bool read;
}

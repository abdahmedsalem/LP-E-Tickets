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

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      timeLabel: json['timeLabel']?.toString() ?? '',
      actionLabel: json['actionLabel']?.toString(),
      actionRoute: json['actionRoute']?.toString(),
      read: json['read'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'timeLabel': timeLabel,
      'actionLabel': actionLabel,
      'actionRoute': actionRoute,
      'read': read,
    };
  }
}

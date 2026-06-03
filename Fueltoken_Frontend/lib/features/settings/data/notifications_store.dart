import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_item.dart';

/// Notifications utilisateur persistées localement.
class NotificationsStore extends ChangeNotifier {
  NotificationsStore._();
  static final NotificationsStore instance = NotificationsStore._();

  static const _kItemsKey = 'ft_notifications_items';
  static const _kMaxItems = 50;

  final ValueNotifier<int> unreadCount = ValueNotifier(0);
  final List<NotificationItem> _items = [];
  bool _loaded = false;

  List<NotificationItem> get items => List.unmodifiable(_items);

  Future<void> load() async {
    if (_loaded) {
      _recomputeUnread();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kItemsKey);
    _items
      ..clear()
      ..addAll(_decodeItems(raw));
    _loaded = true;
    _recomputeUnread();
    notifyListeners();
  }

  void initCounts() {
    _recomputeUnread();
  }

  Future<void> add(NotificationItem item) async {
    final existingIndex = _items.indexWhere((e) => e.id == item.id);
    if (existingIndex >= 0) {
      _items.removeAt(existingIndex);
    }
    _items.insert(0, item);
    if (_items.length > _kMaxItems) {
      _items.removeRange(_kMaxItems, _items.length);
    }
    _recomputeUnread();
    await _persist();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    for (final item in _items) {
      item.read = true;
    }
    _recomputeUnread();
    await _persist();
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    final item = _items.where((e) => e.id == id).firstOrNull;
    if (item != null) {
      item.read = true;
      _recomputeUnread();
      await _persist();
      notifyListeners();
    }
  }

  void _recomputeUnread() {
    unreadCount.value = _items.where((e) => !e.read).length;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_kItemsKey, encoded);
  }

  List<NotificationItem> _decodeItems(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .where((item) => item.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

extension _FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../models/notification_item.dart';

/// Notifications utilisateur persistÃ©es localement, isolÃ©es par utilisateur.
///
/// Chaque utilisateur a sa propre clÃ© dans SharedPreferences :
/// `ft_notifications_items_<userId>`. Le changement d'utilisateur (login /
/// logout) vide la mÃ©moire et recharge depuis le bon slot.
class NotificationsStore extends ChangeNotifier {
  NotificationsStore._();
  static final NotificationsStore instance = NotificationsStore._();

  static const _kItemsKeyPrefix = 'ft_notifications_items_';
  static const _kMaxItems = 50;

  final ValueNotifier<int> unreadCount = ValueNotifier(0);
  final List<NotificationItem> _items = [];
  bool _loaded = false;
  String? _userId;

  List<NotificationItem> get items => List.unmodifiable(_items);

  String get _itemsKey {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return '${_kItemsKeyPrefix}anonymous';
    return '$_kItemsKeyPrefix$uid';
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Chargement user-scoped (mÃ©thode principale)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Charge les notifications de [userId].
  /// Si l'utilisateur change, vide la mÃ©moire et recharge depuis le bon slot.
  Future<void> loadForUser(String userId) async {
    if (_userId == userId && _loaded) {
      _recomputeUnread();
      return;
    }

    // Changement d'utilisateur : purger la mÃ©moire
    if (_userId != userId) {
      _items.clear();
      _loaded = false;
    }

    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_itemsKey);
    _items
      ..clear()
      ..addAll(_decodeItems(raw));
    await _migratePurchaseItemsIfNeeded();
    _loaded = true;
    _recomputeUnread();
    notifyListeners();
  }

  /// RÃ©initialisation Ã  la dÃ©connexion : purge la mÃ©moire et rÃ©initialise
  /// l'ID utilisateur courant. Les donnÃ©es persistÃ©es restent dans SharedPrefs
  /// et seront rechargÃ©es si l'utilisateur se reconnecte.
  Future<void> clearAndReset() async {
    _items.clear();
    _loaded = false;
    _userId = null;
    _recomputeUnread();
    notifyListeners();
  }

  Future<void> purgeCurrentUserItemsOnce(String purgeKeyPrefix) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final purgeKey = '${purgeKeyPrefix}_$userId';
    if (prefs.getBool(purgeKey) == true) return;

    _items.clear();
    await prefs.remove(_itemsKey);
    await prefs.setBool(purgeKey, true);
    _recomputeUnread();
    notifyListeners();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // CompatibilitÃ© backward (appelÃ© depuis main.dart avant authentification)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> load() async {
    if (_userId != null) {
      return loadForUser(_userId!);
    }
    // Pas encore d'utilisateur connu â€” ne rien charger
    _recomputeUnread();
  }

  Future<void> migrateLegacyContent() async {
    if (!_loaded) {
      // Ne pas charger sans userId â€” sera fait dans loadForUser
      return;
    }
    final dateFixed = _backfillNotificationDatesIfNeeded();
    final changed = await _migratePurchaseItemsIfNeeded();
    if (changed || dateFixed) {
      _recomputeUnread();
      await _persist();
      notifyListeners();
    }
  }

  NotificationItem displayItem(NotificationItem item) =>
      _normalizeReceiptTitle(_normalizeItem(item));

  void initCounts() {
    _recomputeUnread();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // CRUD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> add(NotificationItem item) async {
    // Garantie : ne pas Ã©crire dans un store sans userId
    if (_userId == null) return;

    final existingIndex = _items.indexWhere((e) => e.id == item.id);
    if (existingIndex >= 0) {
      _items.removeAt(existingIndex);
    }
    _items.insert(0, _normalizeItem(item));
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Internals
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _recomputeUnread() {
    unreadCount.value = _items.where((e) => !e.read).length;
  }

  Future<void> _persist() async {
    if (_userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_itemsKey, encoded);
  }

  List<NotificationItem> _decodeItems(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .map(_normalizeItem)
          .where((item) => item.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  NotificationItem _normalizeItem(NotificationItem item) {
    if (!item.id.startsWith('purchase-')) return item;

    final parsed = _extractPurchaseMeta(item.body);
    final amount = item.amountLabel ?? parsed?.$1;
    final date = item.validationDateLabel ?? parsed?.$2;
    final status =
        item.purchaseStatus ??
        (item.body.toLowerCase().contains('rejet') ? 'rejected' : 'approved');
    final body = _purchaseBody(
      status: status,
      amount: amount,
      date: date,
      body: item.body,
      rejectionReason: item.rejectionReason,
    );

    return NotificationItem(
      id: item.id,
      title: item.title,
      body: body,
      timeLabel: item.timeLabel,
      notificationDateLabel: item.notificationDateLabel,
      purchaseStatus: status,
      amountLabel: amount,
      validationDateLabel: date,
      rejectionReason: item.rejectionReason,
      purchaseLines: item.purchaseLines,
      transferLines: item.transferLines,
      transferPartyPhone: item.transferPartyPhone,
      qrExpirationLines: item.qrExpirationLines,
      read: item.read,
    );
  }

  NotificationItem _normalizeReceiptTitle(NotificationItem item) {
    if (!(item.category == 'receipt' || item.id.startsWith('transfer-'))) {
      return item;
    }
    return NotificationItem(
      id: item.id,
      title: 'Réception',
      body: item.body,
      timeLabel: item.timeLabel,
      notificationDateLabel: item.notificationDateLabel,
      category: item.category,
      purchaseStatus: item.purchaseStatus,
      amountLabel: item.amountLabel,
      validationDateLabel: item.validationDateLabel,
      rejectionReason: item.rejectionReason,
      purchaseLines: item.purchaseLines,
      transferLines: item.transferLines,
      transferPartyPhone: item.transferPartyPhone,
      qrExpirationLines: item.qrExpirationLines,
      qrPublicCode: item.qrPublicCode,
      actionLabel: item.actionLabel,
      actionRoute: item.actionRoute,
      read: item.read,
    );
  }

  String _purchaseBody({
    required String status,
    required String? amount,
    required String? date,
    required String body,
    required String? rejectionReason,
  }) {
    if (amount == null || date == null) return body;
    if (status == 'rejected') {
      final reason = rejectionReason?.trim();
      if (reason == null || reason.isEmpty) {
        return '$amount â€¢ RejetÃ©e le $date';
      }
      return '$amount â€¢ RejetÃ©e le $date â€¢ Motif: $reason';
    }
    return '$amount â€¢ ValidÃ©e le $date';
  }

  (String amount, String date)? _extractPurchaseMeta(String body) {
    final normalized = body.trim();

    final modern = RegExp(
      r'^(.+?)\s*[â€¢Â·]\s*(?:ValidÃ©e|RejetÃ©e) le\s*(.+?)(?:\s*[â€¢Â·]\s*Motif:.*)?$',
    ).firstMatch(normalized);
    if (modern != null) {
      return (modern.group(1)!.trim(), modern.group(2)!.trim());
    }

    final legacy = RegExp(
      r'tickets pour\s+(.+?)\.\s+(?:ValidÃ©e|RejetÃ©e) le\s+(.+?)(?:\s*[â€¢Â·]\s*Motif:.*)?\.?$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (legacy != null) {
      return (legacy.group(1)!.trim(), legacy.group(2)!.trim());
    }

    return null;
  }

  Future<bool> _migratePurchaseItemsIfNeeded() async {
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      final current = _items[i];
      final normalized = _normalizeItem(current);
      if (normalized.body != current.body ||
          normalized.amountLabel != current.amountLabel ||
          normalized.validationDateLabel != current.validationDateLabel ||
          normalized.purchaseStatus != current.purchaseStatus ||
          normalized.rejectionReason != current.rejectionReason) {
        _items[i] = normalized;
        changed = true;
      }
    }
    return changed;
  }

  bool _backfillNotificationDatesIfNeeded() {
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      final current = _items[i];
      if (current.notificationDateLabel != null &&
          current.notificationDateLabel!.trim().isNotEmpty) {
        continue;
      }
      _items[i] = NotificationItem(
        id: current.id,
        title: current.title,
        body: current.body,
        timeLabel: current.timeLabel,
        notificationDateLabel: current.timeLabel.trim().isNotEmpty
            ? current.timeLabel.trim()
            : Formatters.dateTime(DateTime.now()),
        category: current.category,
        purchaseStatus: current.purchaseStatus,
        amountLabel: current.amountLabel,
        validationDateLabel: current.validationDateLabel,
        rejectionReason: current.rejectionReason,
        purchaseLines: current.purchaseLines,
        transferLines: current.transferLines,
        transferPartyPhone: current.transferPartyPhone,
        qrExpirationLines: current.qrExpirationLines,
        qrPublicCode: current.qrPublicCode,
        actionLabel: current.actionLabel,
        actionRoute: current.actionRoute,
        read: current.read,
      );
      changed = true;
    }
    return changed;
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


import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_environment.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/app_user.dart';
import '../../data/models/purchase_lot.dart';
import '../../data/models/user_role.dart';
import '../../data/services/acpec_purchases_mapper.dart';
import '../../data/services/odoo_fueltoken_facade.dart';
import '../../features/settings/data/notifications_store.dart';
import '../../features/settings/models/notification_item.dart';

class PurchaseValidationNotificationService {
  PurchaseValidationNotificationService._();
  static final PurchaseValidationNotificationService instance =
      PurchaseValidationNotificationService._();

  static const _channelId = 'purchase_validation';
  static const _channelName = 'Validation de commandes';
  static const _channelDescription =
      'Notifications pour les commandes de carnets validÃ©es ou rejetÃ©es';
  static const _prefsPrefix = 'ft_purchase_validation_notified_';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final Set<String> _syncingUserIds = <String>{};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
    await _plugin.initialize(settings: initSettings);

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _initialized = true;
  }

  Future<void> syncForUser(AppUser user) async {
    if (!AppEnvironment.useAcpecLiveData) return;
    if (user.role != UserRole.user) return;
    if (!_syncingUserIds.add(user.id)) return;

    try {
      await initialize();
      // Garantir que le store est scopÃ© Ã  cet utilisateur avant d'Ã©crire
      await NotificationsStore.instance.loadForUser(user.id);

      final raw = await OdooFueltokenFacade().purchasesList(
        const <String, dynamic>{'state': 'terminal'},
      );
      final lots = AcpecPurchasesMapper.fromRpcResult(
        raw,
        clientId: user.id,
        clientName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      );
      final terminalLots = lots.where(
        (lot) =>
            lot.state == PurchaseLotState.approved ||
            lot.state == PurchaseLotState.rejected,
      );
      if (terminalLots.isEmpty) return;

      final notifiedIds = await _loadNotifiedIds(user.id);
      for (final lot in terminalLots) {
        if (notifiedIds.contains(lot.id)) {
          await _refreshStoredNotificationIfNeeded(lot);
          continue;
        }
        notifiedIds.add(lot.id);
        await _emitStatusNotification(lot);
      }
      await _saveNotifiedIds(user.id, notifiedIds);
    } finally {
      _syncingUserIds.remove(user.id);
    }
  }

  Future<void> _emitStatusNotification(PurchaseLot lot) async {
    final item = _buildStoredNotification(lot);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'FuelToken',
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      id: _notificationIdFor(lot),
      title: item.title,
      body: item.body,
      notificationDetails: details,
    );

    await NotificationsStore.instance.add(item);
  }

  Future<void> _refreshStoredNotificationIfNeeded(PurchaseLot lot) async {
    final existing = NotificationsStore.instance.items.where(
      (item) => item.id == 'purchase-${lot.id}',
    );
    final NotificationItem? current = existing.isEmpty ? null : existing.first;
    if (current == null) return;
    if (_hasCompletePurchaseLines(current)) return;

    await NotificationsStore.instance.add(
      _buildStoredNotification(lot, read: current.read),
    );
  }

  bool _hasCompletePurchaseLines(NotificationItem item) {
    if (item.purchaseLines.isEmpty) return false;
    for (final line in item.purchaseLines) {
      if (line.label.trim().isEmpty) return false;
      if (line.amountLabel.trim().isEmpty) return false;
      if (line.carnetCount <= 0) return false;
    }
    return true;
  }

  NotificationItem _buildStoredNotification(
    PurchaseLot lot, {
    bool read = false,
  }) {
    final effectiveDate = lot.state == PurchaseLotState.rejected
        ? (lot.rejectedAt ?? lot.validationDate ?? DateTime.now())
        : (lot.approvedAt ?? lot.validationDate ?? DateTime.now());
    final amountLabel = Formatters.money(lot.totalAmount);
    final dateLabel = Formatters.dateTime(effectiveDate);
    final lines = lot.lines
        .map(
          (line) => NotificationPurchaseLineItem(
            label: _lineLabel(line),
            quantityLabel:
                '${Formatters.numberFr(line.carnetCount)} carnet${line.carnetCount > 1 ? 's' : ''}',
            amountLabel: Formatters.money(line.lineAmount),
            faceValue: line.faceValue,
            carnetSize: line.carnetSize,
            carnetCount: line.carnetCount,
          ),
        )
        .toList(growable: false);
    final isRejected = lot.state == PurchaseLotState.rejected;
    final title = isRejected
        ? 'Commande de carnets rejetÃ©e'
        : 'Commande de carnets validÃ©e';
    final rejectionReason = isRejected ? lot.rejectionReason : null;
    final body = isRejected
        ? _rejectedBody(amountLabel, dateLabel, rejectionReason)
        : '$amountLabel â€¢ ValidÃ©e le $dateLabel';

    return NotificationItem(
      id: 'purchase-${lot.id}',
      title: title,
      body: body,
      timeLabel: dateLabel,
      purchaseStatus: isRejected ? 'rejected' : 'approved',
      amountLabel: amountLabel,
      validationDateLabel: dateLabel,
      rejectionReason: rejectionReason,
      purchaseLines: lines,
      read: read,
    );
  }

  String _rejectedBody(
    String amountLabel,
    String dateLabel,
    String? rejectionReason,
  ) {
    final reason = rejectionReason == null || rejectionReason.trim().isEmpty
        ? null
        : rejectionReason.trim();
    if (reason == null) {
      return '$amountLabel â€¢ RejetÃ©e le $dateLabel';
    }
    return '$amountLabel â€¢ RejetÃ©e le $dateLabel â€¢ Motif: $reason';
  }

  String _lineLabel(PurchaseLine line) {
    final rawName = line.carnetTypeName.trim();
    if (rawName.isNotEmpty) {
      return Formatters.normalizeCarnetTypeLabel(
        rawName,
        fallbackSize: line.carnetSize,
        fallbackFaceValue: line.faceValue,
      );
    }
    return Formatters.carnetTypeLabel(line.carnetSize, line.faceValue);
  }

  int _notificationIdFor(PurchaseLot lot) {
    final raw = lot.id.hashCode ^ lot.publicCode.hashCode;
    return raw & 0x7fffffff;
  }

  Future<Set<String>> _loadNotifiedIds(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefsPrefix$userId');
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveNotifiedIds(String userId, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsPrefix$userId', jsonEncode(ids.toList()));
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_environment.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/app_user.dart';
import '../../data/models/business_transaction.dart';
import '../../data/models/purchase_lot.dart';
import '../../data/models/user_role.dart';
import '../../data/models/qr_token.dart';
import '../../data/services/acpec_purchases_mapper.dart';
import '../../data/services/acpec_qr_mapper.dart';
import '../../data/services/acpec_transactions_mapper.dart';
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
      'Notifications pour les commandes de carnets validées ou rejetées';
  static const _prefsPrefix = 'ft_purchase_validation_notified_';
  static const _qrPrefsPrefix = 'ft_qr_expiration_notified_';
  static const _stationConsumptionPrefsPrefix =
      'ft_station_consumption_notified_';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final Set<String> _syncingUserIds = <String>{};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      // flutter_local_notifications and dart:io Platform checks are not
      // available on Flutter Web. Keep web runtime clean and let in-app
      // notification screens fetch their data separately.
      _initialized = true;
      return;
    }

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
    if (kIsWeb) return;
    if (!AppEnvironment.useAcpecLiveData) return;
    if (user.role != UserRole.user) return;
    if (!_syncingUserIds.add(user.id)) return;

    try {
      await initialize();
      await NotificationsStore.instance.loadForUser(user.id);

      final notifiedIds = await _loadNotifiedIds(user.id);
      await _syncPurchaseNotifications(user, notifiedIds);
      await _syncTransferNotifications(user, notifiedIds);
      await _saveNotifiedIds(user.id, notifiedIds);

      final stationPrefsInitialized = await _hasNotifiedIds(
        user.id,
        prefix: _stationConsumptionPrefsPrefix,
      );
      final stationNotifiedIds = await _loadNotifiedIds(
        user.id,
        prefix: _stationConsumptionPrefsPrefix,
      );
      await _syncStationConsumptionNotifications(
        user,
        stationNotifiedIds,
        emitNew: stationPrefsInitialized,
      );
      await _saveNotifiedIds(
        user.id,
        stationNotifiedIds,
        prefix: _stationConsumptionPrefsPrefix,
      );

      final qrNotifiedIds = await _loadNotifiedIds(
        user.id,
        prefix: _qrPrefsPrefix,
      );
      await _syncQrExpirationNotifications(user, qrNotifiedIds);
      await _saveNotifiedIds(user.id, qrNotifiedIds, prefix: _qrPrefsPrefix);
    } finally {
      _syncingUserIds.remove(user.id);
    }
  }

  Future<void> _syncPurchaseNotifications(
    AppUser user,
    Set<String> notifiedIds,
  ) async {
    try {
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

      for (final lot in terminalLots) {
        final key = 'purchase-${lot.id}';
        if (notifiedIds.contains(key) ||
            NotificationsStore.instance.items.any((item) => item.id == key)) {
          await _refreshStoredPurchaseNotificationIfNeeded(lot);
          continue;
        }
        notifiedIds.add(key);
        unawaited(_emitStatusNotification(lot));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[purchase-validation] sync des notifications de commandes ignorée: ${e.runtimeType}',
        );
      }
    }
  }

  Future<void> _syncTransferNotifications(
    AppUser user,
    Set<String> notifiedIds,
  ) async {
    final transfers = await _loadReceivedTransfers(user);
    for (final tx in transfers) {
      final key = 'transfer-${tx.id}';
      if (notifiedIds.contains(key) ||
          NotificationsStore.instance.items.any((item) => item.id == key)) {
        await _refreshStoredTransferNotificationIfNeeded(tx);
        continue;
      }
      notifiedIds.add(key);
      await _emitTransferNotification(tx);
    }
  }

  Future<void> _syncStationConsumptionNotifications(
    AppUser user,
    Set<String> notifiedIds, {
    required bool emitNew,
  }) async {
    try {
      final consumptions = await _loadStationConsumptionTransactions(user);
      for (final tx in consumptions) {
        final key = _stationConsumptionKey(tx);
        if (notifiedIds.contains(key) ||
            NotificationsStore.instance.items.any((item) => item.id == key)) {
          continue;
        }
        notifiedIds.add(key);
        if (!emitNew) {
          continue;
        }
        await _emitStationConsumptionNotification(user, tx);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[purchase-validation] sync des notifications de consommation station ignorée: ${e.runtimeType}',
        );
      }
    }
  }

  Future<void> _syncQrExpirationNotifications(
    AppUser user,
    Set<String> notifiedIds,
  ) async {
    final raw = await OdooFueltokenFacade().qrList(const <String, dynamic>{});
    final qrs = AcpecQrMapper.listFromRpc(
      raw,
      ownerId: user.id,
      ownerName: user.name,
      companyId: AppEnvironment.companyIdForUser(user),
    );

    final now = DateTime.now().toLocal();
    for (final qr in qrs) {
      if (qr.state != QrState.active) continue;

      final expiration = _resolveQrExpiration(qr);
      if (expiration == null) continue;
      final expirationLocal = expiration.toLocal();
      if (!now.isBefore(expirationLocal)) continue;

      for (final threshold in const [
        _QrExpirationThreshold.days7,
        _QrExpirationThreshold.hours24,
      ]) {
        if (!_isQrExpirationDue(now, expirationLocal, threshold)) {
          continue;
        }
        final key = _qrExpirationKey(qr, threshold);
        if (notifiedIds.contains(key) ||
            NotificationsStore.instance.items.any((item) => item.id == key)) {
          continue;
        }
        notifiedIds.add(key);
        await _emitQrExpirationNotification(qr, expirationLocal, threshold);
      }
    }
  }

  Future<void> _emitStatusNotification(PurchaseLot lot) async {
    await Future<void>.delayed(const Duration(milliseconds: 2500));

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

  Future<void> _refreshStoredPurchaseNotificationIfNeeded(
    PurchaseLot lot,
  ) async {
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

  Future<void> _emitTransferNotification(BusinessTransaction tx) async {
    final item = _buildTransferNotification(tx);

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
      id: _notificationIdForTransfer(tx),
      title: item.title,
      body: item.body,
      notificationDetails: details,
    );

    await NotificationsStore.instance.add(item);
  }

  Future<void> _emitStationConsumptionNotification(
    AppUser user,
    BusinessTransaction tx,
  ) async {
    final item = await _buildStationConsumptionNotification(user, tx);

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
      id: _notificationIdForStationConsumption(tx),
      title: item.title,
      body: item.body,
      notificationDetails: details,
    );

    await NotificationsStore.instance.add(item);
  }

  Future<void> _emitQrExpirationNotification(
    QrToken qr,
    DateTime expirationLocal,
    _QrExpirationThreshold threshold,
  ) async {
    final item = _buildQrExpirationNotification(qr, expirationLocal, threshold);

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
      id: _notificationIdForQrExpiration(qr, threshold),
      title: item.title,
      body: item.body,
      notificationDetails: details,
    );

    await NotificationsStore.instance.add(item);
  }

  Future<void> _refreshStoredTransferNotificationIfNeeded(
    BusinessTransaction tx,
  ) async {
    final existing = NotificationsStore.instance.items.where(
      (item) => item.id == 'transfer-${tx.id}',
    );
    final NotificationItem? current = existing.isEmpty ? null : existing.first;
    if (current == null) return;
    if (_hasCompleteTransferLines(current)) return;

    await NotificationsStore.instance.add(
      _buildTransferNotification(tx, read: current.read),
    );
  }

  bool _hasCompleteTransferLines(NotificationItem item) {
    if (item.transferLines.isEmpty) return false;
    if ((item.transferPartyPhone ?? '').trim().isEmpty) return false;
    for (final line in item.transferLines) {
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
    final notificationDateLabel = Formatters.dateTime(DateTime.now());
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
        ? 'Commande de carnets rejetée'
        : 'Commande de carnets validée';
    final rejectionReason = isRejected ? lot.rejectionReason : null;
    final body = isRejected
        ? _rejectedBody(amountLabel, dateLabel, rejectionReason)
        : ' • Commande validée le ';

    return NotificationItem(
      id: 'purchase-${lot.id}',
      title: title,
      body: body,
      timeLabel: dateLabel,
      notificationDateLabel: notificationDateLabel,
      purchaseStatus: isRejected ? 'rejected' : 'approved',
      amountLabel: amountLabel,
      validationDateLabel: dateLabel,
      rejectionReason: rejectionReason,
      purchaseLines: lines,
      read: read,
    );
  }

  NotificationItem _buildTransferNotification(
    BusinessTransaction tx, {
    bool read = false,
  }) {
    final dateLabel = Formatters.dateTime(tx.date);
    final notificationDateLabel = Formatters.dateTime(DateTime.now());
    final amountLabel = Formatters.money(tx.totalAmount);
    final party = (tx.transferParty ?? '').trim();
    final lines = tx.lines
        .map(
          (line) => NotificationPurchaseLineItem(
            label: _txLineLabel(line),
            quantityLabel:
                '${Formatters.numberFr(line.qty)} ${tx.isTicketTransfer ? 'ticket' : 'carnet'}${line.qty > 1 ? 's' : ''}',
            amountLabel: Formatters.money(line.amount),
            faceValue: line.faceValue,
            carnetSize: line.carnetSize,
            carnetCount: line.qty,
          ),
        )
        .toList(growable: false);
    final title = tx.transferDisplayTitle;
    final roleLabel = tx.transferPartyRoleLabelForViewer(tx.userId);
    final body = party.isNotEmpty ? '$roleLabel : $party' : roleLabel;

    return NotificationItem(
      id: 'transfer-${tx.id}',
      title: title,
      body: body,
      timeLabel: dateLabel,
      notificationDateLabel: notificationDateLabel,
      category: 'receipt',
      amountLabel: amountLabel,
      validationDateLabel: dateLabel,
      transferLines: lines,
      transferPartyPhone: tx.transferPartyPhone,
      actionRoute: '/transactions',
      actionLabel: 'Voir',
      read: read,
    );
  }

  Future<NotificationItem> _buildStationConsumptionNotification(
    AppUser user,
    BusinessTransaction tx, {
    bool read = false,
  }) async {
    final dateLabel = Formatters.dateTime(tx.date);
    final notificationDateLabel = Formatters.dateTime(DateTime.now());
    final amount = tx.totalAmount.abs();
    final amountLabel = amount > 0 ? Formatters.money(amount) : '';
    final station = (tx.stationName ?? tx.stationId ?? '').trim();

    final title = 'QR consommé';
    final body = _stationConsumptionBody(amountLabel, station);

    return NotificationItem(
      id: _stationConsumptionKey(tx),
      title: title,
      body: body,
      timeLabel: dateLabel,
      notificationDateLabel: notificationDateLabel,
      category: 'station_consumption',
      amountLabel: amountLabel.isEmpty ? null : amountLabel,
      validationDateLabel: dateLabel,
      qrPublicCode: tx.qrPublicCode,
      actionRoute: '/transactions',
      actionLabel: 'Voir',
      read: read,
    );
  }

  String _stationConsumptionBody(String amountLabel, String station) {
    final place = station.isEmpty ? 'en station' : 'à $station';
    if (amountLabel.isEmpty) {
      return 'Utilisation confirmée $place';
    }
    return '$amountLabel utilisés $place';
  }

  NotificationItem _buildQrExpirationNotification(
    QrToken qr,
    DateTime expirationLocal,
    _QrExpirationThreshold threshold, {
    bool read = false,
  }) {
    final amountLabel = Formatters.money(qr.totalAmount);
    final dateLabel = Formatters.dateTime(expirationLocal);
    final notificationDateLabel = Formatters.dateTime(DateTime.now());
    final qrRef = qr.internalRef?.trim();
    final qrRefLabel = qrRef != null && qrRef.isNotEmpty
        ? ' • Référence QR $qrRef'
        : '';
    final qrPublicCode = qr.publicCode.trim();
    final title = threshold == _QrExpirationThreshold.hours24
        ? 'QR expire dans 24h'
        : 'QR expire dans 7 jours';
    final body = '$amountLabel$qrRefLabel • Expire le $dateLabel';

    return NotificationItem(
      id: _qrExpirationKey(qr, threshold),
      title: title,
      body: body,
      timeLabel: dateLabel,
      notificationDateLabel: notificationDateLabel,
      category: 'qr_expiration',
      amountLabel: amountLabel,
      validationDateLabel: dateLabel,
      qrPublicCode: qrPublicCode.isEmpty ? null : qrPublicCode,
      qrExpirationLines: [
        NotificationQrExpirationLineItem(
          faceValue: qr.totalAmount,
          quantityLabel:
              '${Formatters.numberFr(qr.totalQty)} ticket${qr.totalQty > 1 ? 's' : ''}',
          expirationLabel: dateLabel,
          lotLabel: threshold.displayLabel,
        ),
      ],
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
      return '$amountLabel • Rejetée le $dateLabel';
    }
    return '$amountLabel • Rejetée le $dateLabel • Motif: $reason';
  }

  bool _isQrExpirationDue(
    DateTime nowLocal,
    DateTime expirationLocal,
    _QrExpirationThreshold threshold,
  ) {
    final remaining = expirationLocal.difference(nowLocal);
    if (remaining.isNegative) return false;

    switch (threshold) {
      case _QrExpirationThreshold.days7:
        return remaining <= const Duration(days: 7) &&
            remaining > const Duration(hours: 24);
      case _QrExpirationThreshold.hours24:
        return remaining <= const Duration(hours: 24);
    }
  }

  DateTime? _resolveQrExpiration(QrToken qr) {
    final direct = qr.expiresAt;
    if (direct != null) return direct;
    if (qr.lines.isEmpty) return null;
    final dates = qr.lines
        .map((line) => line.expirationDate)
        .where((date) => date.year > 1970)
        .toList(growable: false);
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.first;
  }

  String _lineLabel(PurchaseLine line) {
    final label = Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackCode: line.carnetTypeCode,
    );
    return label.isNotEmpty ? label : 'Carnet';
  }

  String _txLineLabel(TransactionLine line) {
    final label = Formatters.carnetTypeLabelFromServer(
      line.carnetTypeName,
      fallbackCode: line.carnetTypeCode,
    );
    return label.isNotEmpty ? label : 'Carnet';
  }

  Future<List<BusinessTransaction>> _loadStationConsumptionTransactions(
    AppUser user,
  ) async {
    final out = <BusinessTransaction>[];
    final seen = <String>{};
    final now = DateTime.now();
    final dateFrom = now.subtract(const Duration(days: 30));
    const pageSize = 50;
    const maxPages = 6;

    for (var page = 0; page < maxPages; page++) {
      final raw = await OdooFueltokenFacade().transactions({
        'date_from': _apiDateTime(dateFrom),
        'date_to': _apiDateTime(now),
        'limit': pageSize,
        'offset': page * pageSize,
      });
      final parsed = AcpecTransactionsMapper.parsePage(
        raw,
        userId: user.id,
        userName: user.name,
        requestedLimit: pageSize,
        requestedOffset: page * pageSize,
      );
      final batch = parsed.items
          .where((tx) => tx.type == TxType.stationConsumption)
          .toList(growable: false);
      for (final tx in batch) {
        if (!seen.add(tx.id)) {
          continue;
        }
        out.add(tx);
      }
      if (!parsed.hasMore || parsed.items.length < pageSize) {
        break;
      }
    }

    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  String _stationConsumptionKey(BusinessTransaction tx) {
    return 'station-consumption-${tx.id}';
  }

  Future<List<BusinessTransaction>> _loadReceivedTransfers(AppUser user) async {
    final out = <BusinessTransaction>[];
    final seen = <String>{};
    final now = DateTime.now();
    final dateFrom = DateTime(now.year, 1, 1);
    const pageSize = 50;
    const maxPages = 6;

    for (var page = 0; page < maxPages; page++) {
      final raw = await OdooFueltokenFacade().transactions({
        'date_from': _apiDateTime(dateFrom),
        'date_to': _apiDateTime(now),
        'limit': pageSize,
        'offset': page * pageSize,
      });
      final parsed = AcpecTransactionsMapper.parsePage(
        raw,
        userId: user.id,
        userName: user.name,
        requestedLimit: pageSize,
        requestedOffset: page * pageSize,
      );
      final batch = parsed.items
          .where((tx) => tx.type == TxType.carnetReceived)
          .toList(growable: false);
      for (final tx in batch) {
        if (!seen.add(tx.id)) continue;
        out.add(tx);
      }
      if (!parsed.hasMore || parsed.items.length < pageSize) {
        break;
      }
    }

    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  int _notificationIdFor(PurchaseLot lot) {
    final raw = lot.id.hashCode ^ lot.publicCode.hashCode;
    return raw & 0x7fffffff;
  }

  int _notificationIdForTransfer(BusinessTransaction tx) {
    final raw = tx.id.hashCode ^ tx.date.millisecondsSinceEpoch.hashCode;
    return raw & 0x7fffffff;
  }

  int _notificationIdForStationConsumption(BusinessTransaction tx) {
    final raw =
        _stationConsumptionKey(tx).hashCode ^
        tx.date.millisecondsSinceEpoch.hashCode;
    return raw & 0x7fffffff;
  }

  int _notificationIdForQrExpiration(
    QrToken qr,
    _QrExpirationThreshold threshold,
  ) {
    final raw = qr.id.hashCode ^ threshold.id.hashCode;
    return raw & 0x7fffffff;
  }

  String _qrExpirationKey(QrToken qr, _QrExpirationThreshold threshold) {
    return 'qr-${qr.id}-${threshold.id}';
  }

  String _apiDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  Future<bool> _hasNotifiedIds(
    String userId, {
    String prefix = _prefsPrefix,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$prefix$userId');
  }

  Future<Set<String>> _loadNotifiedIds(
    String userId, {
    String prefix = _prefsPrefix,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$prefix$userId');
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveNotifiedIds(
    String userId,
    Set<String> ids, {
    String prefix = _prefsPrefix,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$prefix$userId', jsonEncode(ids.toList()));
  }
}

enum _QrExpirationThreshold {
  days7,
  hours24;

  Duration get duration {
    switch (this) {
      case _QrExpirationThreshold.days7:
        return const Duration(days: 7);
      case _QrExpirationThreshold.hours24:
        return const Duration(hours: 24);
    }
  }

  String get id {
    switch (this) {
      case _QrExpirationThreshold.days7:
        return '7d';
      case _QrExpirationThreshold.hours24:
        return '24h';
    }
  }

  String get displayLabel {
    switch (this) {
      case _QrExpirationThreshold.days7:
        return 'Alerte 7 jours';
      case _QrExpirationThreshold.hours24:
        return 'Alerte 24h';
    }
  }
}

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
      'Notifications pour les commandes de carnets validées';
  static const _prefsPrefix = 'ft_purchase_validation_notified_';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

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

    await initialize();

    final raw = await OdooFueltokenFacade().purchasesList(
      const <String, dynamic>{},
    );
    final lots = AcpecPurchasesMapper.fromRpcResult(
      raw,
      clientId: user.id,
      clientName: user.name,
      companyId: AppEnvironment.companyIdForUser(user),
    );
    final approvedLots = lots
        .where((lot) => lot.state == PurchaseLotState.approved)
        .toList();
    if (approvedLots.isEmpty) return;

    final notifiedIds = await _loadNotifiedIds(user.id);
    for (final lot in approvedLots) {
      if (notifiedIds.contains(lot.id)) continue;
      notifiedIds.add(lot.id);
      await _emitValidatedNotification(lot);
    }
    await _saveNotifiedIds(user.id, notifiedIds);
  }

  Future<void> _emitValidatedNotification(PurchaseLot lot) async {
    final title = 'Commande de carnets validée';
    final body =
        'Votre commande ${lot.internalRef} a été validée. '
        '${Formatters.numberFr(lot.totalFaces)} tickets sont maintenant disponibles.';
    final payload = '/purchases/${Uri.encodeComponent(lot.id)}';
    final notificationId = _notificationIdFor(lot);

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
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );

    await NotificationsStore.instance.add(
      NotificationItem(
        id: 'purchase-${lot.id}',
        title: title,
        body: body,
        timeLabel: 'Maintenant',
        actionLabel: 'Voir l\'achat',
        actionRoute: payload,
      ),
    );
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

import 'dart:async';
import 'dart:io' show exit, Platform, ProcessSignal;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:go_router/go_router.dart';

import 'core/auth/auth_session_host.dart';
import 'core/auth/auth_token_store.dart';
import 'core/auth/odoo_session_store.dart';
import 'core/bootstrap/production_config_gate.dart'
    show ProductionConfigGateApp, ProductionConfigGateReason;
import 'core/config/app_environment.dart';
import 'core/debug/acpec_network_startup_log.dart';
import 'core/notifications/purchase_validation_notification_service.dart';
import 'core/router/app_router.dart';
import 'core/settings/app_preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/client_history_refresh_bus.dart';
import 'core/utils/faces_refresh_bus.dart';
import 'core/utils/purchases_refresh_bus.dart';
import 'core/utils/qr_refresh_bus.dart';
import 'core/utils/wallet_refresh_bus.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/settings/data/notifications_store.dart';

Future<void> _clearPersistedAuthOnDesktopInterrupt() async {
  if (kIsWeb) return;
  void install(ProcessSignal signal) {
    try {
      signal.watch().listen((_) {
        Future<void>(() async {
          await AuthTokenStore.clear();
          await OdooSessionStore.clear();
          exit(0);
        });
      });
    } catch (_) {}
  }

  try {
    if (Platform.isLinux || Platform.isMacOS) {
      install(ProcessSignal.sigint);
      install(ProcessSignal.sigterm);
    } else if (Platform.isWindows) {
      install(ProcessSignal.sigint);
    }
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _clearPersistedAuthOnDesktopInterrupt();
  if (AppEnvironment.blockReleaseWithoutApi) {
    runApp(
      const ProductionConfigGateApp(
        reason: ProductionConfigGateReason.missingApi,
      ),
    );
    return;
  }
  if (AppEnvironment.blockReleaseInsecureApi) {
    runApp(
      const ProductionConfigGateApp(
        reason: ProductionConfigGateReason.insecureApi,
      ),
    );
    return;
  }
  debugPrintAcpecNetworkSummary();
  await initializeDateFormatting('en');
  await initializeDateFormatting('fr_FR');
  await initializeDateFormatting('ar');
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppColors.background,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const FuelTokenApp());
}

class FuelTokenApp extends StatefulWidget {
  const FuelTokenApp({super.key});

  @override
  FuelTokenAppState createState() => FuelTokenAppState();
}

class FuelTokenAppState extends State<FuelTokenApp>
    with WidgetsBindingObserver {
  late final AuthBloc _authBloc;
  late final GoRouter _router;
  String _localeCode = AppPreferences.defaultLocaleCode;
  ThemeMode _themeMode = ThemeMode.light;
  Timer? _notificationPollTimer;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authBloc = AuthBloc();
    AuthSessionHost.instance.attach(
      () => _authBloc.add(const AuthSessionExpiredRequested()),
    );
    _authSubscription = _authBloc.stream.listen((state) {
      if (state.status == AuthStatus.authenticated && state.user != null) {
        // Charger le store pour CET utilisateur (isole les notifications par compte)
        unawaited(
          NotificationsStore.instance
              .loadForUser(state.user!.id)
              .then((_) => _purgeReceivedClientNotifications())
              .then((_) => _syncUserNotifications()),
        );
      } else if (state.status == AuthStatus.unauthenticated) {
        // Déconnexion : purger la mémoire pour ne pas exposer les données
        // de l'ancien utilisateur au prochain login
        unawaited(NotificationsStore.instance.clearAndReset());
      }
    });
    _authBloc.add(const AuthHydrateRequested());
    _router = AppRouter.build(_authBloc);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await reloadPreferences();
    await NotificationsStore.instance.load();
    NotificationsStore.instance.initCounts();
    await PurchaseValidationNotificationService.instance.initialize();
    _startNotificationPolling();
    unawaited(_syncUserNotifications());
  }

  void _startNotificationPolling() {
    _notificationPollTimer?.cancel();
    _notificationPollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_syncUserNotifications()),
    );
  }

  Future<void> _syncUserNotifications() async {
    final user = _authBloc.state.user;
    if (user == null || !AppEnvironment.useAcpecLiveData) return;
    try {
      await PurchaseValidationNotificationService.instance.syncForUser(user);
    } catch (_) {}
  }

  Future<void> _purgeReceivedClientNotifications() async {
    await NotificationsStore.instance.purgeCurrentUserItemsOnce(
      'remove_received_client_notifications_v1',
    );
  }

  Future<void> reloadPreferences() async {
    final locale = await AppPreferences.localeCode();
    final dark = await AppPreferences.darkMode();
    if (!mounted) return;
    setState(() {
      _localeCode = locale;
      _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    });
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: dark ? const Color(0xFF0F172A) : AppColors.background,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: dark
            ? const Color(0xFF1E293B)
            : AppColors.surface,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Bumper tous les buses au retour en premier plan pour forcer
      // le rechargement de toutes les données potentiellement périmées.
      WalletRefreshBus.instance.bump();
      QrRefreshBus.instance.bump();
      FacesRefreshBus.instance.bump();
      ClientHistoryRefreshBus.instance.bump();
      PurchasesRefreshBus.instance.bump();
      unawaited(_syncUserNotifications());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationPollTimer?.cancel();
    _authSubscription?.cancel();
    AuthSessionHost.instance.detach();
    _authBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _authBloc,
      child: MaterialApp.router(
        title: 'FuelToken',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        locale: AppPreferences.localeFromCode(_localeCode),
        supportedLocales: const [Locale('fr'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: _router,
      ),
    );
  }
}

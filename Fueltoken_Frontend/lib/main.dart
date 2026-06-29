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
import 'core/router/app_router.dart';
import 'core/settings/app_preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/notifications/purchase_validation_notification_service.dart';
import 'core/utils/client_history_refresh_bus.dart';
import 'core/utils/faces_refresh_bus.dart';
import 'core/utils/purchases_refresh_bus.dart';
import 'core/utils/qr_refresh_bus.dart';
import 'core/utils/wallet_refresh_bus.dart';
import 'data/models/user_role.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/settings/data/notifications_store.dart';
import 'package:google_fonts/google_fonts.dart';

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

  // Les telephones de validation/production peuvent ne pas avoir acces
  // a fonts.gstatic.com. Ne jamais bloquer l'app sur un telechargement
  // runtime des polices Google Fonts.
  GoogleFonts.config.allowRuntimeFetching = false;
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
  static const Duration _idleLogoutDelay = Duration(seconds: 30);
  static const Duration _purchaseNotificationPollDelay = Duration(seconds: 2);

  late final AuthBloc _authBloc;
  late final GoRouter _router;
  String _localeCode = AppPreferences.defaultLocaleCode;
  ThemeMode _themeMode = ThemeMode.light;
  Timer? _idleLogoutTimer;
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
        if (_shouldAutoLogout(state.user!.role)) {
          _scheduleIdleLogout();
        } else {
          _cancelIdleLogout();
        }
        // Charger le store pour CET utilisateur.
        unawaited(NotificationsStore.instance.loadForUser(state.user!.id));
        unawaited(
          PurchaseValidationNotificationService.instance.syncForUser(
            state.user!,
          ),
        );
        _scheduleNotificationPolling();
      } else if (state.status == AuthStatus.unauthenticated) {
        _cancelIdleLogout();
        _cancelNotificationPolling();
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
  }

  void _scheduleIdleLogout() {
    if (!_shouldAutoLogout(_authBloc.state.user?.role)) return;
    _idleLogoutTimer?.cancel();
    _idleLogoutTimer = Timer(_idleLogoutDelay, _handleIdleLogout);
  }

  void _cancelIdleLogout() {
    _idleLogoutTimer?.cancel();
    _idleLogoutTimer = null;
  }

  void _scheduleNotificationPolling() {
    final user = _authBloc.state.user;
    if (user == null || user.role != UserRole.user) return;
    _notificationPollTimer?.cancel();
    _notificationPollTimer = Timer.periodic(_purchaseNotificationPollDelay, (
      _,
    ) {
      final currentUser = _authBloc.state.user;
      if (!mounted ||
          currentUser == null ||
          currentUser.role != UserRole.user) {
        return;
      }
      unawaited(
        PurchaseValidationNotificationService.instance.syncForUser(currentUser),
      );
    });
  }

  void _cancelNotificationPolling() {
    _notificationPollTimer?.cancel();
    _notificationPollTimer = null;
  }

  void _recordUserActivity() {
    if (!_shouldAutoLogout(_authBloc.state.user?.role)) return;
    _scheduleIdleLogout();
  }

  void _handleIdleLogout() {
    if (!mounted) return;
    if (!_shouldAutoLogout(_authBloc.state.user?.role)) return;
    _authBloc.add(const AuthLogoutRequested());
  }

  // Patch session longue : ne plus détruire la session mobile après 30 secondes
  // d'inactivité. Le futur comportement attendu est un verrouillage local PIN,
  // sans effacement du refresh token ni révocation backend.
  bool _shouldAutoLogout(UserRole? role) => false;

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
      _recordUserActivity();
      // Bumper tous les buses au retour en premier plan pour forcer
      // le rechargement de toutes les données potentiellement périmées.
      WalletRefreshBus.instance.bump();
      QrRefreshBus.instance.bump();
      FacesRefreshBus.instance.bump();
      ClientHistoryRefreshBus.instance.bump();
      PurchasesRefreshBus.instance.bump();

      final currentUser = _authBloc.state.user;
      if (currentUser != null && currentUser.role == UserRole.user) {
        unawaited(
          PurchaseValidationNotificationService.instance.syncForUser(
            currentUser,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelIdleLogout();
    _cancelNotificationPolling();
    _authSubscription?.cancel();
    AuthSessionHost.instance.detach();
    _authBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _authBloc,
      child: MouseRegion(
        opaque: false,
        onHover: (_) => _recordUserActivity(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _recordUserActivity(),
          onPointerMove: (_) => _recordUserActivity(),
          onPointerSignal: (_) => _recordUserActivity(),
          onPointerUp: (_) => _recordUserActivity(),
          onPointerCancel: (_) => _recordUserActivity(),
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
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_environment.dart';
import '../../core/models/client_session.dart';
import '../../domain/models/user_role.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/screens/forgot_otp_flow_screens.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/language_selection_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/register_verify_otp_screen.dart';
import '../../features/auth/screens/session_pin_lock_screen.dart';
import '../../features/auth/screens/activation_pending_screen.dart';
import '../../features/home/screens/client_shell_scaffold.dart';
import '../../features/portfolio/screens/client_portfolio_screen.dart';
import '../../features/portfolio/screens/faces_detail_screen.dart';
import '../../features/home/screens/user_home_screen.dart';
import '../../features/purchases/screens/submit_purchase_screen.dart';
import '../../features/qr/generation/screens/emit_qr_screen.dart';
import '../../features/qr/detail/screens/qr_detail_screen.dart';
import '../../features/portfolio/screens/qr_list_screen.dart';
import '../../features/qr/retirer/screens/retirer_qr_screen.dart';
import '../../features/qr/separation/screens/separer_qr_screen.dart';
import '../../features/transfer/screens/transfer_carnets_screen.dart';
import '../../features/transfer/screens/transfer_tickets_screen.dart';
import '../../features/auth/screens/acpec_connection_step1_screen.dart';
import '../../features/settings/screens/notifications_screen.dart';
import '../../features/profile/screens/client_profile_screen.dart';
import '../../features/station/scan/scan_screen.dart';
import '../../features/station/scan/station_manual_qr_screen.dart';
import '../../features/station/historique_consommation/station_consumption_history_screen.dart';
import '../../features/station/accueil/station_home_screen.dart';
import '../../features/station/profile/station_profile_screen.dart';
import '../../features/station/accueil/stations_map_screen.dart';
import '../../features/station/accueil/station_shell_scaffold.dart';
import '../../features/history/screens/transactions_screen.dart';
import '../../features/operations/screens/operations_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../data/repositories/transfer_repository.dart';
import '../../features/transfer/controllers/transfer_carnets_controller.dart';
import '../../features/transfer/controllers/transfer_tickets_controller.dart';
import '../../data/repositories/purchase_repository.dart';
import '../../features/purchases/controllers/purchase_controller.dart';
import '../../data/repositories/profile_repository.dart';
import '../../features/profile/controllers/profile_controller.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../features/settings/controllers/notifications_controller.dart';
import '../../data/repositories/station_repository.dart';
import '../../features/station/controllers/station_controller.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/repositories/qr_actions_repository.dart';
import '../../features/qr/shared/controllers/qr_actions_controller.dart';
import '../../features/qr/separation/controllers/qr_separation_controller.dart';
import '../../data/repositories/portfolio_repository.dart';
import '../../data/repositories/history_repository.dart';
import '../../features/portfolio/controllers/portfolio_controller.dart';
import '../../features/history/controllers/history_controller.dart';
import '../../data/repositories/qr_generation_repository.dart';
import '../../features/qr/generation/controllers/qr_generation_controller.dart';

class AppRouter {
  static ClientSession _clientSession(AuthBloc authBloc) {
    final user = authBloc.state.user;
    return ClientSession(
      isLiveDataEnabled: AppEnvironment.useAcpecLiveData,
      ownerId: user?.id,
      ownerName: user?.name ?? '',
      companyId: AppEnvironment.companyIdForUser(user?.companyId),
      ownerPhone: user?.phone ?? '',
      isDeviceTrusted: user?.isDeviceTrusted ?? false,
      stationName: user?.stationName,
      stationId: user?.stationId,
      ownerEmail: user?.email ?? '',
    );
  }

  static GoRouter build(AuthBloc authBloc) {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: _AuthListenable(authBloc),
      redirect: (_, state) {
        final auth = authBloc.state;
        final loggedIn = auth.status == AuthStatus.authenticated;
        final locked = auth.status == AuthStatus.locked;
        final loc = state.matchedLocation;
        final atPinLockRoute = loc == '/session-pin-lock';
        final atActivationPendingRoute = loc == '/activation-pending';
        final hasUser = auth.user != null;
        final deviceSecurityRestricted =
            hasUser &&
            (auth.user!.isDeviceActivationPending ||
                auth.user!.isDeviceBlocked);
        final atAuthRoute = {
          '/splash',
          '/language-selection',
          '/login',
          '/onboarding',
          '/session-pin-lock',
          '/register',
          '/register/verify-otp',
          '/forgot-password',
          '/forgot-password/verify-otp',
          '/forgot-password/reset',
        }.contains(loc);

        if (deviceSecurityRestricted) {
          if (!atActivationPendingRoute) return '/activation-pending';
          return null;
        }
        if (atActivationPendingRoute) {
          if (loggedIn && auth.user != null) return _homeFor(auth.user!.role);
          if (locked && auth.user != null) return '/session-pin-lock';
          return '/login';
        }

        if (locked && !atPinLockRoute) return '/session-pin-lock';
        if (!locked && atPinLockRoute) {
          if (loggedIn && auth.user != null) return _homeFor(auth.user!.role);
          return '/login';
        }
        if (!loggedIn && !locked && !atAuthRoute) return '/login';
        if (loggedIn && atAuthRoute) {
          switch (auth.user!.role) {
            case UserRole.user:
              return '/home';
            case UserRole.admin:
              return '/home';
            case UserRole.station:
              return '/station/home';
          }
        }

        if (loggedIn) {
          final role = auth.user!.role;
          if (role == UserRole.admin && loc.startsWith('/admin')) {
            return '/home';
          }
          if (role == UserRole.station && loc == '/transactions') {
            return '/station/journal';
          }
          if (role == UserRole.station && _isClientAppPath(loc)) {
            return '/station/home';
          }
          if (loc.startsWith('/settings') && role != UserRole.user) {
            return _homeFor(role);
          }
          if (loc == '/notifications' && role != UserRole.user) {
            return _homeFor(role);
          }
          if (loc.startsWith('/admin')) {
            return '/home';
          }
          if ((loc == '/station' || loc.startsWith('/station/')) &&
              role != UserRole.station) {
            return _homeFor(role);
          }
          if (loc == '/home' && role != UserRole.user) return _homeFor(role);
          if (loc == '/station' && role == UserRole.station) {
            return '/station/home';
          }
        }
        return null;
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(
          path: '/language-selection',
          builder: (_, _) => const LanguageSelectionScreen(),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingScreen(),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/activation-pending',
          builder: (_, _) => const ActivationPendingScreen(),
        ),
        GoRoute(
          path: '/session-pin-lock',
          builder: (_, _) => const SessionPinLockScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (_, _) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/forgot-password/verify-otp',
          builder: (context, st) {
            final x = st.extra;
            if (x is! ForgotOtpRouteArgs) {
              return Scaffold(
                body: Center(
                  child: Text(
                    AppLocalizations.of(context).authRestartFromForgotPin,
                  ),
                ),
              );
            }
            return ForgotVerifyOtpScreen(args: x);
          },
        ),
        GoRoute(
          path: '/forgot-password/reset',
          builder: (context, st) {
            final x = st.extra;
            if (x is! ForgotResetRouteArgs) {
              return Scaffold(
                body: Center(
                  child: Text(AppLocalizations.of(context).authRestartFromOtp),
                ),
              );
            }
            return ResetPasswordAfterOtpScreen(args: x);
          },
        ),
        GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
        GoRoute(
          path: '/register/verify-otp',
          builder: (ctx, state) {
            final x = state.extra;
            return RegisterVerifyOtpScreen(
              args: x is RegisterOtpRouteArgs ? x : null,
            );
          },
        ),

        // Client shell: 4 onglets visibles + la branche Réglages masquée.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return ClientShellScaffold(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    child: UserHomeScreen(
                      session: _clientSession(authBloc),
                      portfolioController: PortfolioController(
                        repository: PortfolioRepository(),
                      ),
                      walletRepository: WalletRepository(),
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/wallet',
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    child: OperationsScreen(
                      session: _clientSession(authBloc),
                      role: authBloc.state.user?.role ?? UserRole.user,
                      controller: HistoryController(
                        repository: HistoryRepository(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/transactions',
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    child: TransactionsScreen(
                      session: _clientSession(authBloc),
                      role: authBloc.state.user?.role ?? UserRole.user,
                      controller: HistoryController(
                        repository: HistoryRepository(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/portfolio',
                  pageBuilder: (context, state) => const NoTransitionPage<void>(
                    child: ClientPortfolioScreen(),
                  ),
                  routes: [
                    GoRoute(
                      path: 'faces',
                      pageBuilder: (context, state) => NoTransitionPage<void>(
                        child: FacesDetailScreen(
                          session: _clientSession(authBloc),
                          controller: PortfolioController(
                            repository: PortfolioRepository(),
                          ),
                        ),
                      ),
                    ),
                    GoRoute(
                      path: 'qr',
                      pageBuilder: (context, state) => NoTransitionPage<void>(
                        child: QrListScreen(
                          session: _clientSession(authBloc),
                          controller: PortfolioController(
                            repository: PortfolioRepository(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    child: ClientProfileScreen(
                      user: authBloc.state.user,
                      onLogout: () => authBloc.add(const AuthLogoutRequested()),
                      controller: ProfileController(
                        repository: ProfileRepository(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(path: '/faces', redirect: (_, _) => '/portfolio/faces'),
        GoRoute(path: '/qr', redirect: (_, _) => '/portfolio/qr'),
        GoRoute(
          path: '/settings/acpec-step1',
          builder: (_, _) => const AcpecConnectionStep1Screen(),
        ),
        GoRoute(
          path: '/settings/acpec-step2',
          builder: (_, _) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => NotificationsScreen(
            user: authBloc.state.user,
            controller: NotificationsController(
              repository: NotificationsRepository(),
            ),
          ),
        ),
        GoRoute(
          path: '/stations-map',
          builder: (_, _) => StationsMapScreen(
            controller: StationController(repository: StationRepository()),
          ),
        ),
        GoRoute(
          path: '/settings/stations-map',
          redirect: (_, _) => '/stations-map',
        ),
        GoRoute(
          path: '/purchases/new',
          builder: (_, _) => SubmitPurchaseScreen(
            session: _clientSession(authBloc),
            controller: PurchaseController(repository: PurchaseRepository()),
          ),
        ),
        GoRoute(
          path: '/qr/emit',
          builder: (_, _) => EmitQrScreen(
            session: _clientSession(authBloc),
            controller: QrGenerationController(
              repository: QrGenerationRepository(),
            ),
          ),
        ),
        GoRoute(
          path: '/transfer-carnets',
          builder: (_, _) => TransferCarnetsScreen(
            session: _clientSession(authBloc),
            controller: TransferCarnetsController(
              repository: TransferRepository(),
            ),
          ),
        ),
        GoRoute(
          path: '/transfer-tickets',
          builder: (_, _) => TransferTicketsScreen(
            session: _clientSession(authBloc),
            controller: TransferTicketsController(
              repository: TransferRepository(),
            ),
          ),
        ),
        GoRoute(
          path: '/qr/:id',
          builder: (_, st) {
            final repository = QrActionsRepository();
            return QrDetailScreen(
              session: _clientSession(authBloc),
              qrId: st.pathParameters['id']!,
              justEmitted: st.uri.queryParameters['emitted'] == '1',
              actionsController: QrActionsController(repository: repository),
              separationController: QrSeparationController(
                repository: repository,
              ),
            );
          },
        ),
        GoRoute(
          path: '/qr/:id/retirer',
          builder: (_, st) => RetirerQrScreen(
            session: _clientSession(authBloc),
            qrId: st.pathParameters['id']!,
            controller: QrActionsController(repository: QrActionsRepository()),
          ),
        ),
        GoRoute(
          path: '/qr/:id/separer',
          builder: (_, st) => SeparerQrScreen(
            session: _clientSession(authBloc),
            qrId: st.pathParameters['id']!,
            controller: QrSeparationController(
              repository: QrActionsRepository(),
            ),
          ),
        ),
        GoRoute(path: '/station', redirect: (_, _) => '/station/home'),
        GoRoute(
          path: '/station/journal',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            child: StationConsumptionHistoryScreen(
              session: _clientSession(authBloc),
              controller: StationController(repository: StationRepository()),
            ),
          ),
        ),

        GoRoute(
          path: '/station/manual',
          builder: (_, _) => StationManualQrScreen(
            session: _clientSession(authBloc),
            controller: StationController(repository: StationRepository()),
          ),
        ),
        // Station shell: home, scan, profile
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return StationShellScaffold(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/station/home',
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    child: StationHomeScreen(session: _clientSession(authBloc)),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/station/scan',
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    child: ScanScreen(
                      session: _clientSession(authBloc),
                      stationController: StationController(
                        repository: StationRepository(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/station/profile',
                  pageBuilder: (context, state) => NoTransitionPage<void>(
                    child: StationProfileScreen(
                      session: _clientSession(authBloc),
                      onLogout: () => authBloc.add(const AuthLogoutRequested()),
                      controller: StationController(
                        repository: StationRepository(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        GoRoute(path: '/admin', redirect: (_, _) => '/home'),
      ],
    );
  }

  static String _homeFor(UserRole role) {
    switch (role) {
      case UserRole.user:
        return '/home';
      case UserRole.admin:
        return '/home';
      case UserRole.station:
        return '/station/home';
    }
  }

  /// Screens reserved for the client profile. Admins should not land here.
  static bool _isClientAppPath(String loc) {
    if (loc == '/home' ||
        loc == '/faces' ||
        loc == '/transactions' ||
        loc == '/stations-map') {
      return true;
    }
    if (loc.startsWith('/settings')) return true;
    if (loc.startsWith('/portfolio')) return true;
    if (loc == '/notifications') return true;
    if (loc.startsWith('/purchases')) return true;
    if (loc.startsWith('/transfer-')) return true;
    if (loc.startsWith('/qr')) return true;
    if (loc.startsWith('/wallet')) return true;
    return false;
  }
}

/// Adapter so GoRouter can listen to Bloc state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._bloc) {
    _sub = _bloc.stream.listen((_) => notifyListeners());
  }

  final AuthBloc _bloc;
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

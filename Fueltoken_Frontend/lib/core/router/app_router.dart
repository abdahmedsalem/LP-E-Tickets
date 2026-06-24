import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/user_role.dart';
import '../../features/admin/screens/admin_home_screen.dart';
import '../../features/admin/screens/admin_lots_screen.dart';
import '../../features/admin/screens/admin_more_screen.dart';
import '../../features/admin/screens/admin_profile_screen.dart';
import '../../features/admin/screens/admin_purchase_detail_screen.dart';
import '../../features/admin/screens/admin_reports_screen.dart';
import '../../features/admin/screens/admin_shell_scaffold.dart';
import '../../features/admin/screens/admin_stations_screen.dart';
import '../../features/admin/screens/admin_submitted_purchases_screen.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/screens/forgot_otp_flow_screens.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/register_verify_otp_screen.dart';
import '../../features/auth/screens/session_pin_lock_screen.dart';
import '../../features/auth/screens/activation_pending_screen.dart';
import '../../features/home/screens/client_shell_scaffold.dart';
import '../../features/home/screens/faces_detail_screen.dart';
import '../../features/home/screens/user_home_screen.dart';
import '../../features/purchases/screens/purchase_detail_screen.dart';
import '../../features/purchases/screens/purchases_list_screen.dart';
import '../../features/purchases/screens/submit_purchase_screen.dart';
import '../../features/qr/screens/emit_qr_screen.dart';
import '../../features/qr/screens/qr_detail_screen.dart';
import '../../features/qr/screens/qr_list_screen.dart';
import '../../features/qr/screens/retirer_qr_screen.dart';
import '../../features/qr/screens/separer_qr_screen.dart';
import '../../features/qr/screens/transfer_carnets_screen.dart';
import '../../features/settings/screens/acpec_connection_step1_screen.dart';
import '../../features/settings/screens/notifications_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/station/screens/scan_screen.dart';
import '../../features/station/screens/station_consumption_history_screen.dart';
import '../../features/station/screens/station_home_screen.dart';
import '../../features/station/screens/station_profile_screen.dart';
import '../../features/station/screens/station_shell_scaffold.dart';
import '../../features/transactions/screens/transactions_screen.dart';

class AppRouter {
  static GoRouter build(AuthBloc authBloc) {
    return GoRouter(
      initialLocation: '/login',
      refreshListenable: _AuthListenable(authBloc),
      redirect: (_, state) {
        final auth = authBloc.state;
        final loggedIn = auth.status == AuthStatus.authenticated;
        final locked =
            auth.status == AuthStatus.locked ||
            auth.status == AuthStatus.pinSetupRequired;
        final loc = state.matchedLocation;
        final atPinLockRoute = loc == '/session-pin-lock';
        final atActivationPendingRoute = loc == '/activation-pending';
        final hasUser = auth.user != null;
        final deviceActivationPending =
            hasUser && auth.user!.isDeviceActivationPending;
        final atAuthRoute = {
          '/login',
          '/session-pin-lock',
          '/register',
          '/register/verify-otp',
          '/forgot-password',
          '/forgot-password/verify-otp',
          '/forgot-password/reset',
        }.contains(loc);

        if (deviceActivationPending) {
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
              return '/admin';
            case UserRole.station:
              return '/station/home';
          }
        }

        if (loggedIn) {
          final role = auth.user!.role;
          if (role == UserRole.admin && loc.startsWith('/purchases/new')) {
            return null;
          }
          if (role == UserRole.admin && _isClientAppPath(loc)) {
            return '/admin';
          }
          if (loc.startsWith('/settings') && role != UserRole.user) {
            return _homeFor(role);
          }
          if (loc == '/notifications' && role != UserRole.user) {
            return _homeFor(role);
          }
          if (loc.startsWith('/admin') && role != UserRole.admin) {
            return _homeFor(role);
          }
          if (loc.startsWith('/station') && role != UserRole.station) {
            return _homeFor(role);
          }
          if (loc == '/home' && role != UserRole.user) return _homeFor(role);
          if (loc == '/station' && role == UserRole.station) {
            return '/station/home';
          }
          if (role == UserRole.station && loc == '/transactions') {
            return '/station/journal';
          }
        }
        return null;
      },
      routes: [
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
          builder: (_, st) {
            final x = st.extra;
            if (x is! ForgotOtpRouteArgs) {
              return const Scaffold(
                body: Center(child: Text('Reprendre depuis le PIN oublie.')),
              );
            }
            return ForgotVerifyOtpScreen(args: x);
          },
        ),
        GoRoute(
          path: '/forgot-password/reset',
          builder: (_, st) {
            final x = st.extra;
            if (x is! ForgotResetRouteArgs) {
              return const Scaffold(
                body: Center(
                  child: Text('Reprendre depuis la verification OTP.'),
                ),
              );
            }
            return ResetPasswordAfterOtpScreen(args: x);
          },
        ),
        GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
        GoRoute(
          path: '/register/verify-otp',
          builder: (_, st) {
            final x = st.extra;
            if (x is! RegisterOtpRouteArgs) {
              return const Scaffold(
                body: Center(child: Text("Reprendre depuis l'inscription.")),
              );
            }
            return RegisterVerifyOtpScreen(args: x);
          },
        ),
        GoRoute(
          path: '/signup/pending',
          builder: (_, _) {
            return const Scaffold(
              body: Center(child: Text('Compte actif. Connectez-vous.')),
            );
          },
        ),

        // Client shell, 5 tabs
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return ClientShellScaffold(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: UserHomeScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/faces',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: FacesDetailScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/qr',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: QrListScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/transactions',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: TransactionsScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: SettingsScreen()),
                ),
              ],
            ),
          ],
        ),
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
          builder: (_, _) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/purchases',
          builder: (_, _) => const PurchasesListScreen(),
        ),
        GoRoute(
          path: '/purchases/new',
          builder: (_, _) => const SubmitPurchaseScreen(),
        ),
        GoRoute(
          path: '/purchases/:id',
          builder: (_, st) =>
              PurchaseDetailScreen(lotId: st.pathParameters['id']!),
        ),
        GoRoute(path: '/qr/emit', builder: (_, _) => const EmitQrScreen()),
        GoRoute(
          path: '/transfer-carnets',
          builder: (_, _) => const TransferCarnetsScreen(),
        ),
        GoRoute(
          path: '/qr/:id',
          builder: (_, st) => QrDetailScreen(
            qrId: st.pathParameters['id']!,
            justEmitted: st.uri.queryParameters['emitted'] == '1',
          ),
        ),
        GoRoute(
          path: '/qr/:id/retirer',
          builder: (_, st) => RetirerQrScreen(qrId: st.pathParameters['id']!),
        ),
        GoRoute(
          path: '/qr/:id/separer',
          builder: (_, st) => SeparerQrScreen(qrId: st.pathParameters['id']!),
        ),
        GoRoute(path: '/station', redirect: (_, _) => '/station/home'),
        GoRoute(
          path: '/station/journal',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: StationConsumptionHistoryScreen(),
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
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: StationHomeScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/station/scan',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: ScanScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/station/profile',
                  pageBuilder: (context, state) => const NoTransitionPage<void>(
                    child: StationProfileScreen(),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Admin shell, 4 tabs
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return AdminShellScaffold(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: AdminHomeScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin/achats',
                  pageBuilder: (context, state) => const NoTransitionPage<void>(
                    child: AdminSubmittedPurchasesScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin/profile',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: AdminProfileScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin/more',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: AdminMoreScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin/lots',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage<void>(child: AdminLotsScreen()),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/admin/purchases/:id',
          builder: (_, st) =>
              AdminPurchaseDetailScreen(purchaseId: st.pathParameters['id']!),
        ),
        GoRoute(
          path: '/admin/accounts/:id',
          builder: (_, _) {
            return const Scaffold(
              body: Center(child: Text('Gestion des comptes mobile.')),
            );
          },
        ),
        GoRoute(
          path: '/admin/stations',
          builder: (_, _) => const AdminStationsScreen(),
        ),
        GoRoute(
          path: '/admin/reports',
          builder: (_, _) => const AdminReportsScreen(),
        ),
      ],
    );
  }

  static String _homeFor(UserRole role) {
    switch (role) {
      case UserRole.user:
        return '/home';
      case UserRole.admin:
        return '/admin';
      case UserRole.station:
        return '/station/home';
    }
  }

  /// Screens reserved for the client profile. Admins should not land here.
  static bool _isClientAppPath(String loc) {
    if (loc == '/home' || loc == '/faces' || loc == '/transactions') {
      return true;
    }
    if (loc.startsWith('/settings')) return true;
    if (loc == '/notifications') return true;
    if (loc.startsWith('/purchases')) return true;
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

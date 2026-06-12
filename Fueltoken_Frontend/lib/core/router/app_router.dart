import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/user_role.dart';
import '../../features/admin/screens/admin_carnets_screen.dart';
import '../../features/admin/screens/admin_home_screen.dart';
import '../../features/admin/screens/admin_lots_screen.dart';
import '../../features/admin/screens/admin_more_screen.dart';
import '../../features/admin/screens/admin_profile_screen.dart';
import '../../features/admin/screens/admin_purchase_detail_screen.dart';
import '../../features/admin/screens/admin_submitted_purchases_screen.dart';
import '../../features/admin/screens/admin_reports_screen.dart';
import '../../features/admin/screens/admin_shell_scaffold.dart';
import '../../features/admin/screens/admin_stations_screen.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/screens/forgot_otp_flow_screens.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/register_verify_otp_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/home/screens/faces_detail_screen.dart';
import '../../features/home/screens/client_shell_scaffold.dart';
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
import '../../features/station/screens/scan_screen.dart';
import '../../features/station/screens/station_home_screen.dart';
import '../../features/station/screens/station_profile_screen.dart';
import '../../features/station/screens/station_consumption_history_screen.dart';
import '../../features/settings/screens/acpec_connection_step1_screen.dart';
import '../../features/settings/screens/notifications_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/station/screens/station_shell_scaffold.dart';
import '../../features/transactions/screens/transactions_screen.dart';

class AppRouter {
  static GoRouter build(AuthBloc authBloc) {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: _AuthListenable(authBloc),
      redirect: (ctx, state) {
        final auth = authBloc.state;
        final loggedIn = auth.status == AuthStatus.authenticated;
        final loc = state.matchedLocation;
        final atAuthRoute = {
          '/login',
          '/register',
          '/register/verify-otp',
          '/splash',
          '/forgot-password',
          '/forgot-password/verify-otp',
          '/forgot-password/reset',
        }.contains(loc);

        if (!loggedIn && !atAuthRoute) return '/login';
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
        // role guards
        if (loggedIn) {
          final role = auth.user!.role;
          final loc = state.matchedLocation;
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
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/forgot-password',
          builder: (_, _) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/forgot-password/verify-otp',
          builder: (ctx, st) {
            final x = st.extra;
            if (x is! ForgotOtpRouteArgs) {
              return const Scaffold(
                body: Center(
                  child: Text('Reprendre depuis mot de passe oublié.'),
                ),
              );
            }
            return ForgotVerifyOtpScreen(args: x);
          },
        ),
        GoRoute(
          path: '/forgot-password/reset',
          builder: (ctx, st) {
            final x = st.extra;
            if (x is! ForgotResetRouteArgs) {
              return const Scaffold(
                body: Center(
                  child: Text('Reprendre depuis la vérification OTP.'),
                ),
              );
            }
            return ResetPasswordAfterOtpScreen(args: x);
          },
        ),
        GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
        GoRoute(
          path: '/register/verify-otp',
          builder: (ctx, st) {
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
          builder: (ctx, st) {
            if (st.extra == Object()) {
              return const Scaffold(
                body: Center(child: Text("Reprendre depuis l'inscription.")),
              );
            }
            return const Scaffold(
              body: Center(child: Text('Compte active. Connectez-vous.')),
            );
          },
        ),

        // user ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â navigation principale (5 onglets)
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

        // station â€” accueil, scan et profil
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

        // admin ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 4 onglets (accent violet)
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
          builder: (_, st) {
            if (st.extra == Object()) {
              return Scaffold(
                appBar: AppBar(title: const Text('Compte mobile')),
                body: const Center(
                  child: Text('Compte introuvable. Revenez à la liste.'),
                ),
              );
            }
            return const Scaffold(
              body: Center(child: Text('Gestion des comptes mobile.')),
            );
          },
        ),
        GoRoute(
          path: '/admin/carnets',
          builder: (_, _) => const AdminCarnetsScreen(),
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

  /// ÃƒÆ’Ã¢â‚¬Â°crans rÃƒÆ’Ã‚Â©servÃƒÆ’Ã‚Â©s au profil Ãƒâ€šÃ‚Â« client Ãƒâ€šÃ‚Â» ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â un compte admin ne doit pas sÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢y retrouver par erreur.
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
  late final dynamic _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

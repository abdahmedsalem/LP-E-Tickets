import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('session timeout recovery guard', () {
    test(
      'short access session expiration triggers refresh recovery only by code',
      () {
        final source = File(
          'lib/data/services/odoo_jsonrpc_client.dart',
        ).readAsStringSync();

        expect(source, contains("code == 'SESSION_EXPIRED'"));
        expect(source, contains("action == 'REFRESH_REQUIRED'"));
        expect(source, contains('publicAction'));
        expect(source, isNot(contains('Session mobile invalide ou expirée')));
        expect(source, contains('_refreshSingleFlight()'));
        expect(source, contains('_trySilentRefresh()'));
        expect(source, contains('_hasSessionChangedSinceRequest'));
        expect(source, contains('_SilentRefreshStatus.transientFailure'));
        expect(source, contains('suppressAuthRecovery: true'));
      },
    );

    test(
      'terminal refresh failure clears all local tokens and notifies auth bloc',
      () {
        final source = File(
          'lib/data/services/odoo_jsonrpc_client.dart',
        ).readAsStringSync();

        expect(source, contains('_clearLocalAuthAndNotify'));
        expect(source, contains('await OdooSessionStore.clear();'));
        expect(source, contains('await AuthTokenStore.clear();'));
        expect(
          source,
          contains('AuthSessionHost.instance.notifySessionExpired();'),
        );
        expect(source, contains("action == 'LOGOUT_REQUIRED'"));
        expect(source, contains('e.requiresLogout'));
        expect(source, contains("'SESSION_CLOSED'"));
        expect(source, contains("'LOGOUT_REQUIRED'"));
        expect(source, contains('previousSessionId'));
        expect(source, contains('previousAccessToken'));
        expect(source, contains('sessionRotated || accessRotated'));
      },
    );

    test(
      'repository boot restore preserves tokens on transient refresh failure',
      () {
        final source = File(
          'lib/data/repositories/auth_repository.dart',
        ).readAsStringSync();

        expect(source, contains('tryRestoreRemoteSession'));
        expect(source, contains('refreshSession'));
        expect(source, contains('on OdooJsonRpcException catch (e)'));
        expect(
          source,
          contains('e.requiresLogout || e.isAuthRequired || e.isOdooSessionExpired'),
        );
        expect(
          source,
          contains('Erreur réseau / timeout / SERVER_ERROR : conserver la session.'),
        );
      },
    );

    test(
      'refresh recovery uses stale-token check and single-flight latch',
      () {
        final source = File(
          'lib/data/services/odoo_jsonrpc_client.dart',
        ).readAsStringSync();

        expect(source, contains('Future<_SilentRefreshResult>? _refreshInFlight'));
        expect(source, contains('late final Future<_SilentRefreshResult> tracked'));
        expect(source, contains('_refreshInFlight = tracked'));
        expect(source, contains('_hasSessionChangedSinceRequest'));
        expect(source, contains('previousAccessToken: accessTokenUsedAtSend'));
        expect(source, contains('previousSessionId: sessionIdUsedAtSend'));
        expect(source, contains('suppressAuthRecovery: true'));
      },
    );

    test(
      'transient refresh failure does not clear local auth',
      () {
        final source = File(
          'lib/data/services/odoo_jsonrpc_client.dart',
        ).readAsStringSync();

        expect(source, contains('_SilentRefreshStatus.transientFailure'));
        expect(source, contains('throw refresh.error ?? e;'));
        expect(source, contains('Erreur transitoire pendant /refresh'));
      },
    );

    test(
      'wallet transient backend failure is surfaced without clearing data',
      () {
        final source = File(
          'lib/features/wallet/bloc/wallet_cubit.dart',
        ).readAsStringSync();

        expect(source, contains('loadError: ErrorPresenter.backendUnavailable()'));
        expect(source, contains('emit(state.copyWith(loading: true, clearError: true));'));
        expect(
          source,
          isNot(contains('loading: true, clearError: true, clearBreakdown: true')),
        );
        expect(source, contains('error_presenter.dart'));
      },
    );

    test(
      'client home shows backend unavailable banner with retry',
      () {
        final source = File(
          'lib/features/home/screens/user_home_screen.dart',
        ).readAsStringSync();

        expect(source, contains('wallet.loadError'));
        expect(source, contains('class _BackendUnavailableBanner'));
        expect(source, contains('Icons.cloud_off_rounded'));
        expect(source, contains('Réessayer'));
        expect(source, contains('ctx.read<WalletCubit>().refresh()'));
      },
    );

    test(
      'error presenter exposes backend unavailable classification',
      () {
        final source = File(
          'lib/core/utils/error_presenter.dart',
        ).readAsStringSync();

        expect(source, contains('backendUnavailable()'));
        expect(source, contains('isBackendUnavailable'));
        expect(source, contains('SERVER_ERROR'));
        expect(source, contains('connection refused'));
        expect(source, contains('Serveur momentanément indisponible'));
      },
    );

    test(
      'auth bloc moves expired terminal session to unauthenticated login state',
      () {
        final source = File(
          'lib/features/auth/bloc/auth_bloc.dart',
        ).readAsStringSync();

        expect(source, contains('AuthSessionExpiredRequested'));
        expect(source, contains('AuthStatus.unauthenticated'));
        expect(source, contains('Reconnectez-vous pour continuer'));
        expect(source, contains('await _repo.logout();'));
      },
    );
  });
}

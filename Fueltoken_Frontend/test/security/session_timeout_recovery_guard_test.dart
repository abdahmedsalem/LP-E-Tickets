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
        expect(source, contains('_trySilentRefresh()'));
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
      'repository boot restore also clears both stores if refresh fails',
      () {
        final source = File(
          'lib/data/repositories/auth_repository.dart',
        ).readAsStringSync();

        expect(source, contains('tryRestoreRemoteSession'));
        expect(source, contains('refreshSession'));
        expect(source, contains('await OdooSessionStore.clear();'));
        expect(source, contains('await AuthTokenStore.clear();'));
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

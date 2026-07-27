import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Patch2I login AUTH_REFUSED anti-dead-end guard', () {
    test(
      'AUTH_REFUSED copy suggests checking phone or creating an account',
      () {
        final source = _read('lib/data/services/acpec_public_api_error.dart');

        expect(source, contains("'AUTH_REFUSED'"));
        expect(source, contains('Connexion impossible.'));
        expect(source, contains('Vérifiez le numéro ou le code SMS'));
        expect(source, contains('Vous pouvez aussi créer un compte'));

        expect(source, isNot(contains('Compte inexistant')));
        expect(source, isNot(contains('Aucun compte trouvé')));
        expect(source, isNot(contains('Numéro non enregistré')));
      },
    );

    test('login screen already exposes change phone and signup exits', () {
      final source = _read('lib/features/auth/screens/login_screen.dart');

      expect(source, contains('l10n.authChangePhone'));
      expect(source, contains('l10n.authCreateAnAccount'));
      expect(source, contains("'/register'"));
    });
  });
}

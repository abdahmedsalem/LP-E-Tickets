# Patch 1 — Session longue frontend après OTP

Objectif : après inscription OTP ou session mobile ACPEC existante, un F5 Chrome / redémarrage Flutter ne doit plus renvoyer l'utilisateur vers le login PIN/mot de passe si le refresh token est encore valide.

## Fichiers modifiés

- `lib/data/repositories/auth_repository.dart`
  - `adoptRemoteUser()` sauvegarde désormais `access_token` et `refresh_token` dans `OdooSessionStore`.
  - `tryRestoreRemoteSession()` tente maintenant `/session-check`, puis `/refresh`, puis restaure l'utilisateur.
  - Les tokens ne sont effacés que si le refresh échoue réellement.

- `lib/data/services/odoo_auth_service.dart`
  - Ajout de `refreshSession()`.
  - Le refresh se fait sans ancien `Authorization: Bearer`, avec `refresh_token` en params et `X-ACPEC-Refresh-Token` en header.

- `lib/data/api/acpec_fueltoken_jsonrpc_api.dart`
  - Ajout de `callRouteWithoutSession()` pour les appels techniques comme `/refresh`.

- `lib/main.dart`
  - Désactivation temporaire de l'auto-logout après 30 secondes.
  - Doctrine cible : remplacer plus tard par un verrouillage local PIN sans suppression du refresh token.

## Test attendu

1. Lancer Flutter avec `ODOO_USE_ACPEC_AUTH=true`.
2. Créer un compte.
3. Valider l'OTP fake `000000`.
4. Arriver sur Home.
5. Faire F5 dans Chrome.
6. Résultat attendu : retour automatique à Home après restauration session, sans écran mot de passe/PIN.

## Test refresh automatique

Pour tester la restauration avec access token expiré :

1. Mettre `acpec_mobile_auth.access_token_minutes = 3` côté Odoo.
2. Redémarrer Odoo.
3. Login/inscription OTP.
4. Attendre 4 minutes.
5. F5 Chrome.
6. Résultat attendu : `/refresh` est appelé et l'utilisateur revient sur Home.

Après test, remettre `access_token_minutes = 60`.

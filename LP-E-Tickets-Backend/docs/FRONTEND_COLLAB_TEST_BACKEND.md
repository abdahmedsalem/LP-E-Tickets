# FuelToken — Backend collaboratif frontend/mobile

## Objectif

Le module `acpec_fueltoken_test` n’est pas un module métier FuelToken.

Il fournit une interface d’aide aux développeurs frontend/mobile pour comprendre :

- la structure des endpoints ;
- les paramètres attendus ;
- les réponses JSON ;
- les données échangées pendant les flux d’inscription, OTP, achat, QR, transfert et station ;
- les différences entre `secret_code`, `action_code`, OTP et tokens Bearer.

Cette interface peut être utilisée :

- localement sur un poste développeur ;
- ou à distance sur un VPS de développement/collaboration quand le développeur frontend/mobile ne travaille pas directement sur l’environnement Odoo backend.

## Différence entre module et mode runtime

### `acpec_fueltoken_test`

`acpec_fueltoken_test` est le module Odoo qui contient la console navigateur et le catalogue d’endpoints.

Installer le module ne doit pas, à lui seul, activer des comportements dangereux.

### `ACPEC_FUELTOKEN_TEST_MODE=1`

`ACPEC_FUELTOKEN_TEST_MODE=1` est l’autorisation runtime explicite indiquant que l’environnement est un environnement local/dev/test/collaboration, et non une production.

Quand ce mode est activé, il peut autoriser :

- l’accès à la console `/acpec/fueltoken/test` ;
- le retour `otp_dev_code` / `dev_otp_code` si `otp_dev_mode=True` ;
- les valeurs OTP anti-flood à `0` pour faciliter les tests ;
- l’usage d’un OTP local de test selon le module de test.

### `--test-enable`

`--test-enable` est réservé aux tests automatisés Odoo.

Il ne doit pas être utilisé comme mécanisme normal pour un VPS collaboratif frontend/mobile.

## Environnement VPS collaboratif

Un VPS collaboratif frontend/mobile peut utiliser `acpec_fueltoken_test` si les conditions suivantes sont respectées :

- environnement classé DEV/STAGING/COLLAB, jamais PROD ;
- base de données de test, sans données réelles sensibles ;
- domaine ou URL séparé de la production ;
- accès limité aux développeurs autorisés ;
- firewall, VPN, IP whitelist ou protection reverse proxy recommandés ;
- `ACPEC_FUELTOKEN_TEST_MODE=1` défini explicitement seulement sur cet environnement ;
- jamais d’activation de `ACPEC_FUELTOKEN_TEST_MODE=1` sur le serveur production.

## Règles de sécurité applicables

Même en environnement collaboratif :

- `secret_code` reste le PIN initial / inscription, pas un mot de passe Odoo ;
- `action_code` reste le seul champ accepté pour confirmer une action sensible ;
- `pin`, `action_pin` et `secret_code` ne sont pas acceptés comme alias d’action sensible ;
- les actions sensibles exigent un device trusted ;
- les actions sensibles/idempotentes exigent une `idempotency_key` ;
- le backend calcule le `request_hash`.

## Règle production

En production :

- ne pas activer `ACPEC_FUELTOKEN_TEST_MODE=1` ;
- ne pas exposer `/acpec/fueltoken/test` ;
- ne pas retourner `otp_dev_code` ;
- ne pas désactiver les protections anti-flood OTP avec des valeurs `0` ;
- ne pas utiliser de données ou OTP de test.

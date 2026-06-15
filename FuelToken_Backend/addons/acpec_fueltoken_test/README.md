# ACPEC FuelToken Test

Console navigateur de test pour le bundle FuelToken courant.

## URL

```text
/acpec/fueltoken/test
```

## Rôle du module

Ce module ne fait pas partie du métier FuelToken. Il sert uniquement de console de test pour appeler les endpoints JSON-RPC exposés par :

- `acpec_mobile_auth`
- `acpec_mobile_auth_otp`
- `acpec_fueltoken_api`

## Points importants

- Le module dépend de `acpec_fueltoken_api` et sert uniquement en développement ou recette.
- Les appels protégés utilisent `Authorization: Bearer <access_token>`.
- La console capture automatiquement `access_token` et `refresh_token` après `/verify-otp`. Les routes `/login` et `/password-login` sont conservées comme héritage/dev et ne doivent pas être utilisées comme voie normale.
- `/login` est conservé comme alias hérité de `/password-login` pour compatibilité temporaire, mais le login mobile cible reste OTP -> Bearer tokens.
- Le login mot de passe est désactivé par défaut. Le `secret_code` est désormais un PIN de confirmation mobile, pas un mot de passe Odoo.
- Le mode OTP dev local n’est activé par ce module que si `ACPEC_FUELTOKEN_TEST_MODE=1` est défini.
- Les achats créés par API sont soumis, mais doivent être validés dans le backend pour générer les faces disponibles.
- La consommation station nécessite un utilisateur lié à une station active (`acpec.fuel.station`).

## Sécurité / production

Ce module est strictement réservé au développement local.

Même si le module est installé, les comportements dangereux de test sont inertes sauf si la variable d’environnement suivante est explicitement activée :

    ACPEC_FUELTOKEN_TEST_MODE=1

Sans cette variable :

- l’OTP local fixe `000000` n’est pas utilisé ;
- l’envoi SMS réel n’est pas remplacé ;
- la validation OTP réelle reste active ;
- `otp_dev_mode` n’est pas activé par le hook ;
- la page publique `/acpec/fueltoken/test` retourne 404.

Ce module ne doit pas être présent dans l’`addons_path` de production.


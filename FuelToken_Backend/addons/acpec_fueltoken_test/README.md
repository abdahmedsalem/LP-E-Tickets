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
- La console capture automatiquement `access_token` et `refresh_token` après `/login`, `/password-login` ou `/verify-otp`.
- `/login` est conservé comme alias propre de `/password-login` pour compatibilité Flutter, mais il retourne la même session mobile tokenisée.
- Le login mot de passe est désactivé par défaut et nécessite `acpec_mobile_auth.allow_password_login=True`.
- Le mode OTP dev peut exposer le code avec `acpec_mobile_auth.otp_dev_mode=True`.
- Les achats créés par API sont soumis, mais doivent être validés dans le backend pour générer les faces disponibles.
- La consommation station nécessite un utilisateur lié à une station active (`acpec.fuel.station`).

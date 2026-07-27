# Refonte Odoo FuelToken

Ce bundle est construit sur les modèles existants `acpec.fuel.*`. La refonte ne recrée pas le métier FuelToken ; elle complète l'existant pour que Odoo devienne le backend unique de l'application mobile.

## Modules gardés

- `acpec_mobile_auth`
- `acpec_fueltoken_base`
- `acpec_fueltoken_catalog`
- `acpec_fueltoken_purchase`
- `acpec_fueltoken_core`
- `acpec_fueltoken_api`
- `acpec_fueltoken_reports`
- `acpec_fueltoken_test`

## Module ajouté

- `acpec_mobile_auth_otp`

## Nouveaux modèles

- `acpec.mobile.session` dans `acpec_mobile_auth`
- `acpec.mobile.auth.otp` dans `acpec_mobile_auth_otp`

## Auth mobile

La cible production est :

```text
request-otp -> verify-otp -> access_token / refresh_token -> API FuelToken
```

Le login par mot de passe reste disponible uniquement pour le développement via le paramètre système :

```text
acpec_mobile_auth.allow_password_login = True
```

Par défaut, il est désactivé.

La route `/api/acpec/mobile_auth/v1/login` est conservée comme alias propre de `/api/acpec/mobile_auth/v1/password-login` pour compatibilité Flutter existante. Les deux routes retournent une session mobile tokenisée et ne reposent pas sur le cookie Odoo `session_id`.

## OTP

Routes :

- `/api/acpec/mobile_auth/v1/request-otp`
- `/api/acpec/mobile_auth/v1/verify-otp`

Paramètres système :

- `acpec_mobile_auth.otp_expiration_minutes` par défaut 5
- `acpec_mobile_auth.otp_max_attempts` par défaut 5
- `acpec_mobile_auth.otp_dev_mode` si `True`, le code OTP est retourné dans la réponse API pour faciliter le développement Flutter

## Session mobile

Routes :

- `/api/acpec/mobile_auth/v1/me`
- `/api/acpec/mobile_auth/v1/refresh`
- `/api/acpec/mobile_auth/v1/logout`
- `/api/acpec/mobile_auth/v1/session-check`

Les routes FuelToken acceptent maintenant :

```http
Authorization: Bearer <access_token>
```

## API FuelToken complétée

Routes client existantes conservées et sécurisées par token mobile.

Routes station ajoutées :

- `/api/acpec/fueltoken/v1/station/profile`
- `/api/acpec/fueltoken/v1/station/qr/check`
- `/api/acpec/fueltoken/v1/station/transactions`

Routes admin ajoutées dans `acpec_fueltoken_api/controllers/api_admin.py` :

- carnet types : list/create/update/delete
- purchases : pending/detail/approve/reject
- stations : list/create/update/disable
- reports : summary

## Wallet enrichi

`/api/acpec/fueltoken/v1/mobile/wallet/current` retourne maintenant les totaux existants et :

- `breakdown_by_face_value`
- `breakdown_by_carnet_type`
- `near_expiration_faces`
- `expired_faces`

## Nettoyage

- Correction des textes UTF-8 corrompus dans `acpec_fueltoken_core/models/fuel_qr.py`.
- Extension des menus de reporting existants.
- Aucun modèle métier `acpec.fuel.*` n'a été recréé.

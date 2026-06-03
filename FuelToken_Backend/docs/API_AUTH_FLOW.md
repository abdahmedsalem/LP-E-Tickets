# Flux d'authentification mobile Odoo

Odoo devient le backend unique. La session mobile officielle est portÃ©e par `acpec.mobile.session` et utilisÃ©e avec :

```http
Authorization: Bearer <access_token>
```

Le cookie Odoo `session_id` n'est pas le mÃ©canisme principal de l'application mobile.

## 1. Auth production : OTP

### Demande OTP

Route : `/api/acpec/mobile_auth/v1/request-otp`

Payload :

```json
{
  "identifier": "36632006",
  "purpose": "login"
}
```

RÃ©ponse :

```json
{
  "ok": true,
  "success": true,
  "data": {
    "challenge_id": 1,
    "challenge_ref": "OTP/2026/000001",
    "expires_at": "2026-05-12 19:30:00",
    "delivery": "configured_provider"
  }
}
```

En dÃ©veloppement, activer :

```text
acpec_mobile_auth.otp_dev_mode = True
```

La rÃ©ponse inclura `dev_otp_code`.

### VÃ©rification OTP

Route : `/api/acpec/mobile_auth/v1/verify-otp`

Payload :

```json
{
  "challenge_id": 1,
  "code": "123456",
  "device_uid": "android-device-id",
  "platform": "android",
  "app_version": "1.0.0"
}
```

RÃ©ponse :

```json
{
  "ok": true,
  "success": true,
  "data": {
    "access_token": "...",
    "refresh_token": "...",
    "token_type": "Bearer",
    "uid": 7,
    "profile": "user"
  }
}
```

## 2. Auth dÃ©veloppement : password login

Route officielle dev : `/api/acpec/mobile_auth/v1/password-login`

Alias compatible Flutter existant : `/api/acpec/mobile_auth/v1/login`

Les deux routes appellent la mÃªme logique et retournent la mÃªme session mobile tokenisÃ©e. Elles sont contrÃ´lÃ©es par :

```text
acpec_mobile_auth.allow_password_login = True
```

Par dÃ©faut, la valeur doit rester `False`.

Payload :

```json
{
  "identifier": "36632006",
  "secret_code": "123456",
  "device_uid": "android-device-id",
  "platform": "android",
  "app_version": "1.0.0"
}
```

## 3. Appel API FuelToken

```http
Authorization: Bearer <access_token>
```

## 4. Refresh

Route : `/api/acpec/mobile_auth/v1/refresh`

Le refresh token peut Ãªtre passÃ© dans le payload ou dans le header `X-ACPEC-Refresh-Token`.

Payload :

```json
{
  "refresh_token": "..."
}
```

## 5. Logout

Route : `/api/acpec/mobile_auth/v1/logout`

Header :

```http
Authorization: Bearer <access_token>
```

La session mobile est rÃ©voquÃ©e.

## 5. SMS Chinguisoft configuration

OTP production sends SMS through Chinguisoft using these Odoo config keys:

SMS_PROVIDER = chinguisoft
SMS_URL = https://chinguisoft.com/api/sms/validation
SMS_VALIDATION_KEY = ...
SMS_TOKEN = ...
SMS_DEFAULT_LANG = fr

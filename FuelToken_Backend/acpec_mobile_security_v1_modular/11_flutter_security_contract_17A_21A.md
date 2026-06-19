# Contrat Flutter — sécurité mobile V1 après patches 17A à 21A

Ce contrat décrit ce que l'application Flutter doit respecter côté mobile.

## 1. Authentification

Flutter doit utiliser les endpoints mobile Bearer / OTP uniquement.

Ne pas utiliser :

- login web Odoo ;
- mot de passe Odoo ;
- reset password Odoo ;
- API key Odoo ;
- TOTP/passkey Odoo.

## 2. Profil/session

Flutter doit exploiter les champs de session/profil suivants quand ils sont retournés :

- `mobile_pin_set`
- `mobile_pin_required`
- `device_uid`
- `device_trust_state`
- `device_trusted_at`
- `device_trust_required_for_sensitive`

## 3. Device pending_trust

Si `device_trust_state != trusted` :

- les lectures normales peuvent rester accessibles ;
- les actions sensibles doivent être bloquées ou précédées d'un message clair ;
- message recommandé : `Ce device est en attente de validation back-office.`

## 4. Actions sensibles

Avant un endpoint sensible, Flutter doit demander un code d'action et l'envoyer au backend.

Champ recommandé :

```json
{
  "action_code": "1234"
}
```

Clés acceptées pour compatibilité backend :

- `action_code`
- `action_pin`
- `pin`
- `secret_code`

Flutter doit utiliser `action_code` pour éviter la confusion avec le PIN local de déverrouillage app.

## 5. Endpoints sensibles V1

Envoyer `action_code` sur :

- `/api/acpec/fueltoken/v1/mobile/purchases/create`
- `/api/acpec/fueltoken/v1/mobile/carnets/transfer`
- `/api/acpec/fueltoken/v1/admin/purchases/approve`
- `/api/acpec/fueltoken/v1/admin/purchases/reject`
- `/api/acpec/fueltoken/v1/admin/stations/create`
- `/api/acpec/fueltoken/v1/admin/stations/update`
- `/api/acpec/fueltoken/v1/admin/stations/disable`

## 6. Erreurs attendues

Flutter doit gérer :

- `ACCESS_ERROR` : compte non autorisé, device non trusted, device blocked, PIN incorrect ;
- `VALIDATION_ERROR` : `action_code` absent ou invalide ;
- `RATE_LIMITED` : OTP/PIN temporairement limité.

## 7. À ne pas faire

Ne pas créer ou utiliser un endpoint générique `/verify-pin`.

Le PIN local Flutter ne remplace pas le PIN serveur d'action sensible.

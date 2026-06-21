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

Clé unique acceptée par le backend pour confirmer une action sensible :

- `action_code`

Les alias `action_pin`, `pin` et `secret_code` sont interdits sur les actions sensibles et doivent produire une erreur de validation. `secret_code` reste réservé au signup / initialisation du PIN mobile ; il ne doit jamais être réutilisé comme nom de champ de confirmation d'action.

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

## Additif patch22A — classification des endpoints sensibles

Les endpoints suivants sont classés sensibles et exigent désormais device trusted + PIN serveur action_code :

- /api/acpec/fueltoken/v1/mobile/qr/issue
- /api/acpec/fueltoken/v1/mobile/qr/retirer
- /api/acpec/fueltoken/v1/mobile/qr/separer
- /api/acpec/fueltoken/v1/station/qr/use
- /api/acpec/fueltoken/v1/admin/carnet-types/create
- /api/acpec/fueltoken/v1/admin/carnet-types/update
- /api/acpec/fueltoken/v1/admin/carnet-types/delete

Les endpoints suivants restent en authentification simple, sans PIN serveur :

- /api/acpec/fueltoken/v1/mobile/qr/list
- /api/acpec/fueltoken/v1/mobile/qr/detail
- /api/acpec/fueltoken/v1/station/profile
- /api/acpec/fueltoken/v1/station/qr/check
- /api/acpec/fueltoken/v1/station/transactions
- /api/acpec/fueltoken/v1/admin/carnet-types/list

Règle doctrinale : toute mutation de valeur économique doit passer par _require_sensitive_action_pin(...). Les lectures, previews et checks non mutatifs restent en authentification mobile simple.


## Additif patch23A — idempotency_key obligatoire sur mutations économiques

Les endpoints suivants exigent désormais idempotency_key en plus du device trusted et du PIN serveur action_code :

- /api/acpec/fueltoken/v1/mobile/purchases/create
- /api/acpec/fueltoken/v1/mobile/qr/issue
- /api/acpec/fueltoken/v1/mobile/qr/retirer
- /api/acpec/fueltoken/v1/mobile/qr/separer
- /api/acpec/fueltoken/v1/mobile/carnets/transfer
- /api/acpec/fueltoken/v1/station/qr/use

Les endpoints de lecture, détail, profil, historique et check non mutatif restent sans idempotency_key obligatoire.

Ce patch a été complété par Patch23B : request_hash est désormais appliqué pour détecter la réutilisation d'une même idempotency_key avec un payload différent.


## Additif patch23B — request_hash idempotence forte

Patch23B ajoute un request_hash déterministe côté backend pour les mutations économiques sensibles déjà protégées par idempotency_key.

Règle appliquée :

- même idempotency_key + même request_hash : retry/replay autorisé selon l'objet existant ;
- même idempotency_key + request_hash différent : refus idempotency_conflict.

Le request_hash est calculé côté backend à partir du payload métier stable. Les champs secrets ou techniques suivants sont exclus du hash :

- action_code
- action_pin
- pin
- secret_code
- idempotency_key
- access_token
- refresh_token
- token
- password

Les modèles runtime qui stockent désormais request_hash :

- acpec.fuel.purchase
- acpec.fuel.qr
- acpec.fuel.carnet.transfer
- acpec.fuel.transaction

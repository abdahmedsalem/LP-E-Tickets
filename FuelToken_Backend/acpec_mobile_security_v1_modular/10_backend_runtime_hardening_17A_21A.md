# Backend runtime hardening réalisé — patches 17A à 21A

Ce fichier résume l'état backend effectivement mis en place dans le dépôt FuelToken après les patches 17A à 21A.

## 1. Baseline mobile-only

Tout utilisateur mobile est un utilisateur Odoo technique mais fonctionnellement mobile-only.

Baseline obligatoire :

- `base.group_portal`
- `acpec_mobile_auth.group_mobile_auth_user`
- `mobile_only = True`
- `share = True`

Groupes interdits pour un mobile-only :

- `base.group_user`
- `base.group_public`
- `acpec_mobile_auth.group_mobile_auth_admin`
- `acpec_fueltoken_base.group_fuel_admin`

Les rôles sensibles ne sont pas choisis par le mobile. Ils sont accordés par le back-office uniquement.

## 2. Mot de passe web et surfaces web

Pour un compte mobile-only :

- mot de passe Odoo utilisateur inconnu / inutilisable ;
- login web par mot de passe bloqué ;
- reset password bloqué ;
- API keys bloquées ou nettoyées ;
- TOTP/passkeys bloqués ou nettoyés ;
- session web Odoo refusée.

## 3. États compte mobile

`res.users.mobile_state` contrôle la session mobile :

- `pending` : compte en attente d'approbation ;
- `approved` : session mobile autorisée ;
- `rejected` : compte refusé ;
- `blocked` : compte bloqué.

Seul `approved` permet une session mobile active.

## 4. Sessions et refresh token

Les sessions mobiles utilisent :

- access token court ;
- refresh token long ;
- hash uniquement en base ;
- rotation du refresh token ;
- fenêtre de grâce courte pour retry réseau.

Un refresh token ne doit jamais réactiver un compte non approuvé.

## 5. Device trust

Toute nouvelle session commence en `pending_trust`.

États device :

- `pending_trust` : lectures possibles, actions sensibles bloquées ;
- `trusted` : actions sensibles possibles si le PIN serveur est correct ;
- `blocked` : actions sensibles bloquées.

Le back-office Mobile Auth Admin peut faire :

- Trust Device ;
- Block Device ;
- Reset Trust.

Ces actions sont protégées côté serveur et tracées dans le chatter.

## 6. PIN serveur pour action sensible

Le `secret_code` saisi à l'inscription initialise un PIN serveur mobile à 4 chiffres.

Ce PIN est stocké séparément du mot de passe Odoo :

- `mobile_pin_hash`
- `mobile_pin_salt`
- `mobile_pin_set`
- `mobile_pin_required`
- `mobile_pin_failed_count`
- `mobile_pin_locked_until`

Le PIN est vérifié par `check_mobile_pin()`.

Ne pas créer de route publique générique `/verify-pin`.

Pour une action sensible, le backend doit appeler :

```python
self._require_sensitive_action_pin(kwargs, purpose='...')
```

Ce helper impose :

1. session Bearer valide ;
2. compte mobile `approved` ;
3. device `trusted` ;
4. PIN serveur correct.

## 7. Endpoints protégés par device trusted + PIN serveur

Client mobile :

- `/api/acpec/fueltoken/v1/mobile/purchases/create`
- `/api/acpec/fueltoken/v1/mobile/carnets/transfer`

Manager/admin mobile :

- `/api/acpec/fueltoken/v1/admin/purchases/approve`
- `/api/acpec/fueltoken/v1/admin/purchases/reject`
- `/api/acpec/fueltoken/v1/admin/stations/create`
- `/api/acpec/fueltoken/v1/admin/stations/update`
- `/api/acpec/fueltoken/v1/admin/stations/disable`

## 8. Points non encore clos

Avant production complète, reclasser :

- QR issue / retirer / séparer ;
- station `qr/use` ;
- admin carnet-types create/update/delete ;
- idempotence forte par `request_hash` ;
- audit métier détaillé des actions sensibles ;
- éventuel modèle `acpec.mobile.device` en V2.

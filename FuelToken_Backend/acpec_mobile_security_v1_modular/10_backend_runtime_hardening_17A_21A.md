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

Ce patch ne remplace pas le futur request_hash. Il rend seulement la clé obligatoire là où le moteur métier accepte déjà une clé idempotente.


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


## Additif Patch23D — action_code canonique

Le backend accepte désormais uniquement `action_code` pour la confirmation PIN serveur des actions sensibles. Les alias `action_pin`, `pin` et `secret_code` sont rejetés par validation afin d'éviter les chemins ambigus et les risques de logs génériques sur `secret_code`.

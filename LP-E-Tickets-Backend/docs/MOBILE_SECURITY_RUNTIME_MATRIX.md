# FuelToken — Matrice sécurité runtime mobile V1

Ce document fige la doctrine runtime appliquée par les patches 24A à 25D.

## Principes non négociables

- Un utilisateur mobile est un utilisateur technique Odoo à usage mobile uniquement.
- Les rôles mobiles sensibles sont attribués par back-office ; ils ne sont jamais choisis par l’utilisateur mobile.
- Un nouveau device n’est pas trusted par défaut.
- `secret_code` sert uniquement au flux d’inscription / OTP / initialisation PIN mobile.
- `action_code` est le seul nom accepté pour confirmer une action sensible côté serveur.
- En V1, `action_code` est le nom API canonique du PIN mobile de confirmation, vérifié côté serveur uniquement dans le contexte d’une action sensible authentifiée.
- Les alias `action_pin`, `pin` et `secret_code` sont rejetés pour les actions sensibles.
- Le PIN mobile de confirmation est soumis à un verrouillage progressif serveur et à un blocage dur nécessitant une réinitialisation après trop d’échecs cumulés.
- Toute action sensible doit vérifier le device trusted via `_require_sensitive_action_pin(...)`.
- Toute action sensible économique ou de configuration doit exiger `idempotency_key`.
- Le serveur calcule `request_hash` via `_compute_idempotency_request_hash(...)`.
- Même `idempotency_key` + même `request_hash` : replay idempotent.
- Même `idempotency_key` + payload différent : `idempotency_conflict`.

## Matrice endpoints sensibles

| Domaine | Méthode contrôleur | Purpose | Trusted device | `action_code` | `idempotency_key` | `request_hash` / conflict | Test runtime dédié |
|---|---|---:|---:|---:|---:|---:|---|
| Mobile achat | `AcpecFuelTokenMobileApi.create_purchase` | `purchase_create` | Oui | Oui | Oui | Oui | `test_purchase_create_runtime_policy.py` |
| Mobile QR | `AcpecFuelTokenMobileApi.issue_qr` | `qr_issue` | Oui | Oui | Oui | Oui | `test_qr_issue_runtime_policy.py` |
| Mobile QR | `AcpecFuelTokenMobileApi.retirer_qr` | `qr_retirer` | Oui | Oui | Oui | Oui | `test_qr_retirer_runtime_policy.py` |
| Mobile QR | `AcpecFuelTokenMobileApi.separer_qr` | `qr_separer` | Oui | Oui | Oui | Oui | `test_qr_separer_runtime_policy.py` |
| Mobile transfert | `AcpecFuelTokenMobileApi.transfer_carnets` | `carnet_transfer` | Oui | Oui | Oui | Oui | `test_carnet_transfer_runtime_policy.py` |
| Station QR | `AcpecFuelTokenStationApi.use_qr` | `station_qr_use` | Oui | Oui | Oui | Oui | `test_station_qr_use_runtime_policy.py` |
| Admin achat | `AcpecFuelTokenAdminApi.purchase_approve` | `purchase_approve` | Oui | Oui | Oui | Oui | `test_admin_purchase_runtime_policy.py` |
| Admin achat | `AcpecFuelTokenAdminApi.purchase_reject` | `purchase_reject` | Oui | Oui | Oui | Oui | `test_admin_purchase_runtime_policy.py` |
| Admin station | `AcpecFuelTokenAdminApi.station_create` | `station_create` | Oui | Oui | Oui | Oui | `test_admin_station_runtime_policy.py` |
| Admin station | `AcpecFuelTokenAdminApi.station_update` | `station_update` | Oui | Oui | Oui | Oui | `test_admin_station_runtime_policy.py` |
| Admin station | `AcpecFuelTokenAdminApi.station_disable` | `station_disable` | Oui | Oui | Oui | Oui | `test_admin_station_runtime_policy.py` |
| Admin type carnet | `AcpecFuelTokenAdminApi.carnet_type_create` | `carnet_type_create` | Oui | Oui | Oui | Oui | `test_admin_carnet_type_runtime_policy.py` |
| Admin type carnet | `AcpecFuelTokenAdminApi.carnet_type_update` | `carnet_type_update` | Oui | Oui | Oui | Oui | `test_admin_carnet_type_runtime_policy.py` |
| Admin type carnet | `AcpecFuelTokenAdminApi.carnet_type_delete` | `carnet_type_delete` | Oui | Oui | Oui | Oui | `test_admin_carnet_type_runtime_policy.py` |

## Endpoints lecture / consultation

Les endpoints suivants restent en authentification mobile régulière selon leur rôle. Ils ne doivent pas demander `action_code`, `idempotency_key` ou `request_hash`, car ils ne modifient pas l’état économique ou de configuration.

| Domaine | Méthode contrôleur | Politique |
|---|---|---|
| Mobile | `purchases`, `purchase_detail`, `transfer_carnets_recipient`, `transfer_list`, `qr_list`, `qr_detail` | Auth mobile standard, pas d’action sensible |
| Station | `profile`, `check_qr`, `station_transactions` | Auth station standard, pas d’action sensible |
| Admin | `carnet_type_list`, `purchases_pending`, `purchase_detail`, `stations_list`, `reports_summary` | Auth manager standard, pas d’action sensible |

## Champs d’idempotence par modèle

| Modèle | Champs |
|---|---|
| `acpec.fuel.purchase` | `idempotency_key`, `request_hash`, `approval_idempotency_key`, `approval_request_hash`, `rejection_idempotency_key`, `rejection_request_hash` |
| `acpec.fuel.qr` | `idempotency_key`, `request_hash` |
| `acpec.fuel.carnet.transfer` | `idempotency_key`, `request_hash` |
| `acpec.fuel.station` | `create_idempotency_key`, `create_request_hash`, `update_idempotency_key`, `update_request_hash`, `disable_idempotency_key`, `disable_request_hash` |
| `acpec.fuel.carnet.type` | `admin_create_idempotency_key`, `admin_create_request_hash`, `admin_update_idempotency_key`, `admin_update_request_hash`, `admin_delete_idempotency_key`, `admin_delete_request_hash` |
| `acpec.fuel.transaction` | `idempotency_key`, `request_hash` pour audit transactionnel |

## Règle pour tout futur endpoint sensible

Tout nouveau endpoint qui crée, modifie, valide, rejette, consomme, émet, retire, sépare, transfère ou désactive une ressource métier doit suivre ce modèle :

```python
user = self._require_sensitive_action_pin(kwargs, purpose='<purpose>')
idempotency_key = self._require_idempotency_key(kwargs, purpose='<purpose>')
request_hash = self._compute_idempotency_request_hash(kwargs, purpose='<purpose>')
```

Pour les endpoints admin, utiliser le helper :

```python
user = self._trusted_admin_user(kwargs, purpose='<purpose>')
```

puis appliquer explicitement `idempotency_key` et `request_hash`.

Pour les endpoints station, utiliser le helper :

```python
station, user = self._trusted_station_user(kwargs, purpose='<purpose>')
```

puis appliquer explicitement `idempotency_key` et `request_hash`.

## Tests de verrouillage

- `test_sensitive_action_pin_gate.py`
- `test_sensitive_device_trust_gate.py`
- `test_sensitive_idempotency_policy.py`
- `test_sensitive_request_hash_policy.py`
- `test_admin_sensitive_inventory_policy.py`
- `test_mobile_security_runtime_docs.py`

Ces tests doivent empêcher les régressions suivantes :

- réintroduction de `action_pin`, `pin` ou `secret_code` comme PIN d’action sensible ;
- ajout d’un endpoint sensible sans trusted device ;
- ajout d’un endpoint sensible sans idempotence forte ;
- confusion entre lecture simple et écriture sensible.

# Changelog

## 2026-06-19 - clarification portal-type mobile_only après POC terrain

- Maintien explicite de `base.group_portal` comme type Odoo obligatoire pour tout mobile user V1.
- Clarification : `base.group_portal` ne signifie pas accès portail web exploitable ; le compte reste fonctionnellement `mobile_only`.
- Ajout de l'exigence `password=False` ou équivalent sans mot de passe web utilisable au provisioning mobile.
- Ajout du blocage explicite reset/signup/API key/passkey/TOTP web pour `mobile_only`.
- Intégration des constats POC terrain : `group_ids` en Odoo 19, user test sans `base.group_portal`, ACL portail larges, règles station encore basées sur `station.user_id` legacy.

## 2026-06-19 - durcissement 09_tests_poc spec exécutable

- Transformation de `09_tests_poc.md` en oracle de tests plus directement exécutable : IDs stables, préconditions, actions, assertions et critères d'échec P0.
- Réordonnancement des POC bloquants selon le flux projet : portal-type user, ACL/with_user, lifecycle user/device, refresh grace, idempotence QR, system_cooldown, config/logs.
- Ajout du mapping règle -> helper/contrainte/test pour éviter les implémentations dispersées.
- Ajout d'un gate de release P0 et de contrôles d'intégrité anti-monolithe parallèle.

## 2026-06-19 - cohérence device/roles/config

- Ajout du canal `system_cooldown` pour devices client `mobile_base_user`, limité à `trust_scope=low_value_only`.
- Ajout de `client_device_cooldown_hours`, `client_system_cooldown_*`, `max_sensitive_role_devices_per_user`.
- Suppression des flags ambigus `new_device_requires_*` comme sources de vérité V1.
- Correction de `INV-SENSITIVE-002` : pas de bypass par step-up ponctuel ; le step-up produit le trust.
- Manager terrain interdit d'accorder ou retirer `mobile_station_user` et `mobile_manager_user`.
- Ajout de la politique `max_active_devices_per_user`.
- Correction de la numérotation 09.7 / 09.8 / 09.9.


## 2026-06-19 - Clôture décisions OPEN-CLIENT-001 / OPEN-MANAGER-001

- `OPEN-CLIENT-001` clôturé : volume cible clients mobiles V1 <= 5000 ; `res.users` par client accepté ; provisioning par back-office ou endpoint contrôlé ; signup portail standard interdit.
- `OPEN-MANAGER-001` clôturé : `manager_field_validation_enabled=False` par défaut ; la validation manager trusted des devices pending est désactivée sauf activation explicite.
- Modules impactés : 00, 01, 04, 08, 09, README, AGENTS, ADR-002, ADR-005.

## 2026-06-19 - alignement runtime patches 17A à 21A

- Ajout de `10_backend_runtime_hardening_17A_21A.md` pour documenter l'état backend réellement implémenté.
- Ajout de `11_flutter_security_contract_17A_21A.md` pour l'intégration Flutter.
- Clarification : `secret_code` initialise le PIN serveur ; les actions sensibles utilisent `action_code`.
- Clarification : `_require_sensitive_action_pin()` englobe session Bearer, compte approved, device trusted et PIN serveur.
- Points restants explicités : QR, station `qr/use`, carnet-types admin, idempotence forte `request_hash`, audit métier.


## Patch23D — action_code canonique

- Suppression de la compatibilité backend `action_pin` / `pin` / `secret_code` pour les PIN d'action sensible.
- `action_code` devient la seule clé acceptée.
- `secret_code` reste réservé au signup / initialisation du PIN mobile.

# Changelog

## Patch36A - Runtime dev/prod fail-closed

- Ajout du gate unique runtime_allows_dev_relax().
- Runtime strict par defaut si environnement absent, inconnu ou production.
- ACPEC_FUELTOKEN_TEST_MODE devient legacy/tripwire readiness, sans effet actif.
- ACPEC_FUELTOKEN_DEV_MODE=1 n'ouvre le mode dev que si ACPEC_ENV, ODOO_ENV ou ENV vaut local, dev ou test.
- Odoo --test-enable ne declenche plus le mode dev relax.
- OTP dev: 000000 accepte uniquement en mode dev explicite, sans exposition publique de otp_dev_code ou dev_otp_code.
- acpec_fueltoken_test mis en quarantaine: plus d'ecriture de parametres securite, plus d'override OTP.
- Tests valides: cible 66 tests OK; elargi 227 tests OK.
- Voir: refonte_runtime_dev_prod_fail_closed_patch36A.md.
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
- Points restants explicités : tests fonctionnels runtime, audit métier détaillé, codes d'erreur API normalisés.

## Patch23D — action_code canonique

- Suppression de la compatibilité backend `action_pin` / `pin` / `secret_code` pour les PIN d'action sensible.
- `action_code` devient la seule clé acceptée.
- `secret_code` reste réservé au signup / initialisation du PIN mobile.

<!-- PATCH32B_CHANGELOG_START -->

## Patch32B — Back-office Device Trust UX

- Ajout de la worklist **Devices à approuver**.
- Ajout d’une logique de candidature `is_device_approval_candidate`.
- Déduplication UX par couple `user_id + device_uid`.
- Domaine défensif : session active, `pending_trust`, `device_uid` présent, utilisateur `mobile_only`, utilisateur `approved`.
- Ajout des champs d’affichage `mobile_phone` et `mobile_user_label`.
- Francisation des boutons back-office device trust.
- Tests ciblés back-office device trust exécutés avec succès : 0 échec, 0 erreur.

Limites assumées :

- Pas encore de modèle stable `acpec.mobile.device`.
- Pas encore de `device_install_uid` Flutter stable.
- Pas encore de refonte du lifecycle session/token.
- Pas encore de révocation automatique des anciennes sessions actives au nouvel OTP.

<!-- PATCH32B_CHANGELOG_END -->

<!-- PATCH32D_CHANGELOG_START -->

## Patch32D — Backend session lifecycle après device UID stable

- Ajout d’une rotation automatique des anciennes sessions actives lors d’un OTP login avec `device_uid` stable `ft-*`.
- Une seule session active est conservée pour un couple `user_id + device_uid` stable après un nouveau login OTP.
- Les anciennes sessions actives sont passées en `rotated` avec `rotated_to_session_id` vers la nouvelle session.
- Les placeholders historiques non fiables comme `flutter-android-local` sont exclus pour compatibilité.
- Le refresh token conserve sa logique existante de rotation avec fenêtre de grâce.
- Aucun nettoyage global automatique des anciennes sessions historiques n’est exécuté.

Validation :

- Test ciblé `TestMobileDeviceTrustBackoffice` : 0 échec, 0 erreur.
- Test élargi : 208 tests, 0 échec, 0 erreur.
- Probe fonctionnel shell : les anciennes sessions `ft-android-*` du même user/device passent en `rotated`, et une seule session active reste.

<!-- PATCH32D_CHANGELOG_END -->

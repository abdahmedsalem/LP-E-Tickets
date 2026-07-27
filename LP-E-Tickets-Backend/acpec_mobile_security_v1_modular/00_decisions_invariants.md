# 00 - Décisions et invariants canoniques

Ce fichier est toujours chargé dans le contexte IA. Il contient les règles courtes qui empêchent les contradictions.

## 0.1 Décisions finales V1

| ID | Décision |
|---|---|
| DEC-ARCH-001 | ACPEC Mobile Auth est un sous-système interne Odoo, pas Firebase/Auth0/Keycloak en V1. |
| DEC-ARCH-002 | `acpec_mobile_auth` reste générique et ne contient pas de logique FuelToken. |
| DEC-CHANNEL-001 | Trois canaux : back-office Odoo, portail Odoo standard, application mobile ACPEC. |
| DEC-USER-001 | Mobile user = `res.users` portal-type + `mobile_only` + groupes mobiles ACPEC. |
| DEC-USER-002 | Tout mobile user a `base.group_portal` et `acpec_mobile_auth.group_mobile_auth_user`. |
| DEC-USER-003 | Un mobile user n'a jamais `base.group_user`, jamais `base.group_public`, jamais groupe admin back-office. |
| DEC-USER-004 | Un mobile user `mobile_only` n'a aucun credential web exploitable : `password=False` ou équivalent, reset/signup/API key/passkey web inutilisables. |
| DEC-ROLE-001 | Le rôle mobile n'est jamais choisi par l'utilisateur mobile. |
| DEC-ROLE-002 | Nouveau mobile user = rôle minimal `mobile_base_user` par défaut, sauf création explicite back-office pour rôle précis. |
| DEC-ROLE-003 | Les rôles sensibles `mobile_station_user` et `mobile_manager_user` ne sont jamais accordés automatiquement après OTP. |
| DEC-ROLE-004 | En V1, le manager ne peut jamais accorder ni retirer un rôle mobile, même `mobile_station_user`. Tous les rôles sont attribués par back-office. |
| DEC-AUTH-001 | Login mobile = téléphone uniquement. Email interdit comme identifiant mobile. |
| DEC-AUTH-002 | OTP = création ou restauration de session serveur. |
| DEC-AUTH-003 | Relance normale = PIN local + refresh/session, pas OTP si session longue valide. |
| DEC-PIN-001 | PIN local = déverrouillage local + confirmation locale ; il ne remplace jamais l'autorisation backend. |
| DEC-STEPUP-001 | Step-up V1 = validation back-office par défaut. Validation manager depuis device déjà trusted seulement si `manager_field_validation_enabled=True`. |
| DEC-STEPUP-002 | OTP SMS n'est pas utilisé comme step-up contre SIM swap, nouveau device ou device non trusted. |
| DEC-STEPUP-003 | `manager_field_validation_enabled=False` par défaut : un manager mobile ne peut pas approuver/truster un device pending sauf activation explicite. |
| DEC-CLIENT-001 | Volume cible clients mobiles V1 : maximum 5000. Le modèle `res.users` par client reste acceptable en V1. |
| DEC-CLIENT-002 | Provisioning client V1 : création back-office ou endpoint d'onboarding contrôlé ; jamais signup portail Odoo standard. |
| DEC-DEVICE-001 | Un nouveau device devient `pending_trust`, jamais automatiquement trusted pour les opérations sensibles. |
| DEC-DEVICE-002 | Rôle attribué != device trusted. |
| DEC-DEVICE-003 | Un device client `mobile_base_user` peut devenir trusted par `system_cooldown` après délai configuré ; ce trust est limité aux opérations client basse valeur. |
| DEC-DEVICE-004 | `system_cooldown` est interdit pour les devices station et manager. |
| DEC-REFRESH-001 | Refresh token rotatif avec fenêtre de grâce courte, fixe, non extensible. |
| DEC-REFRESH-002 | On ne renvoie jamais un refresh token perdu ; on génère une nouvelle paire. |
| DEC-IDEMP-001 | Idempotence garantie par contrainte base, pas par simple check applicatif. |
| DEC-IDEMP-002 | `mobile_session_id` et `device_uid` sont audit, jamais clé d'unicité d'idempotence. |
| DEC-IDEMP-003 | `request_hash` obligatoire pour détecter la réutilisation d'une clé avec payload différent. |
| DEC-ODOO-001 | `with_user(mobile_user)` est l'objectif pour modèles ACPEC, mais doit être validé par POC opération par opération. |
| DEC-ODOO-002 | `sudo()` métier est exceptionnel et exige audit explicite. |
| DEC-ENV-001 | HTTPS obligatoire en production/release. HTTP autorisé uniquement en DEV local explicite. |
| DEC-LOG-001 | Les logs ne contiennent jamais OTP, PIN, access token, refresh token, secret, QR sensible complet. |

## 0.2 Invariants obligatoires

### Utilisateurs et credentials

```text
INV-USER-001: acpec_mobile_only = True => base.group_portal obligatoire.
INV-USER-002: acpec_mobile_only = True => acpec_mobile_auth.group_mobile_auth_user obligatoire.
INV-USER-003: acpec_mobile_only = True => base.group_user interdit.
INV-USER-004: acpec_mobile_only = True => base.group_public interdit.
INV-USER-005: acpec_mobile_only = True => credential web absent/inutilisable ; le provisioning doit forcer `password=False` ou un équivalent Odoo sans mot de passe web.
INV-USER-006: acpec_mobile_state = blocked => aucune session mobile active utilisable.
```


## 0.2.1 Clarification V1 - portal-type mais mobile-only

```text
Le compte mobile FuelToken est techniquement un utilisateur portail Odoo
(base.group_portal), afin d'éviter un utilisateur sans type et de rester
dans le modèle standard Odoo des utilisateurs externes.

Mais il est fonctionnellement mobile-only :
il ne doit pas disposer d'un accès portail web exploitable, ni d'un mot de passe
web utile, ni de reset/signup, ni d'API key/passkey utilisables, ni d'accès
back-office.

Les autorisations métier mobile ne sont pas déduites des ACL portail standard.
Elles sont contrôlées par le backend mobile via session, device trust, rôle mobile,
affectation station/client, idempotence et audit.
```

### Rôles

```text
INV-ROLE-001: OTP réussi != rôle sensible accordé.
INV-ROLE-002: mobile_base_user != mobile_station_user.
INV-ROLE-003: mobile_manager_user != mobile_station_user implicite.
INV-ROLE-004: rôle sensible accordé != device trusted.
INV-ROLE-005: changement de rôle => audit obligatoire.
INV-ROLE-006: manager terrain ne peut jamais accorder ni retirer mobile_station_user.
INV-ROLE-007: manager terrain ne peut jamais accorder ni retirer mobile_manager_user.
```

### Device trust

```text
INV-DEVICE-001: nouveau device => pending_trust pour opérations sensibles.
INV-DEVICE-002: device blocked => session refusée.
INV-DEVICE-003: device pending_trust => consommation QR refusée.
INV-DEVICE-004: trusted_by/trusted_at obligatoires pour transition vers trusted ; pour `system_cooldown`, trusted_by = 'system'.
INV-DEVICE-005: manager pending_trust ne peut valider aucun device.
INV-DEVICE-006: validation_channel = system_cooldown => rôle user = mobile_base_user uniquement, pas station/manager.
INV-DEVICE-007: system_cooldown => opérations haute valeur restent bloquées ou exigent trust back-office.
INV-DEVICE-008: dépassement max_active_devices_per_user => nouvel enrôlement refusé ou validation back-office requise, jamais auto-trusted.
```

### PIN et opérations sensibles

```text
INV-PIN-001: PIN correct != autorisation serveur.
INV-PIN-002: opération sensible => confirmation PIN locale demandée.
INV-SENSITIVE-001: opération sensible exécutée => user approved.
INV-SENSITIVE-002: opération sensible exécutée => device trusted. En V1, le step-up (back-office/manager trusted) est le mécanisme qui rend le device trusted ; il n'existe pas de bypass par step-up ponctuel d'une opération.
INV-SENSITIVE-003: opération sensible exécutée => rôle requis vérifié.
INV-SENSITIVE-004: opération sensible exécutée => société/station/affectation/règles métier vérifiées.
```

### Refresh token

```text
INV-REFRESH-001: refresh_grace_seconds est court : 30 à 60 secondes.
INV-REFRESH-002: previous_refresh_valid_until n'est jamais prolongé par un retry.
INV-REFRESH-003: previous_refresh hors grâce => révocation session.
INV-REFRESH-004: blocage user ou device => effacement des hash refresh current et previous.
```

### Idempotence et QR/ticket

```text
INV-IDEMP-001: unique(operation_type, operator_user_id, idempotency_key) ou unique(company_id, operation_type, operator_user_id, idempotency_key).
INV-IDEMP-002: mobile_session_id et device_uid exclus de la clé unique.
INV-IDEMP-003: même idempotency_key + request_hash différent => idempotency_conflict.
INV-IDEMP-004: ticket consommé = état terminal.
INV-IDEMP-005: un QR/ticket ne peut jamais être consommé deux fois, même avec deux idempotency_key différentes.
```

### Odoo / portal grants

```text
INV-ODOO-001: base.group_portal est requis pour mobile user afin d'éviter un `res.users` sans type, mais ses ACL/rules doivent être auditées et ne constituent jamais une autorisation mobile suffisante.
INV-ODOO-002: aucun endpoint mobile ne doit se contenter de base.group_portal pour autoriser une action.
INV-ODOO-003: tout endpoint sensible passe par un helper unique d'autorisation sensible.
```

## 0.3 Interdits absolus

```text
FORBID-001: Email comme login mobile.
FORBID-002: OTP SMS comme step-up contre SIM swap ou nouveau device.
FORBID-003: Mobile user avec base.group_user.
FORBID-004: Mobile user avec credential web exploitable, y compris mot de passe web, reset/signup, API key, passkey ou TOTP web enrôlable.
FORBID-005: Logs contenant OTP/PIN/tokens/secrets.
FORBID-006: Consommation QR sans idempotence + verrouillage objet.
FORBID-007: Marquer automatiquement un nouveau device station/manager comme trusted après OTP.
FORBID-008: Accorder mobile_manager_user par manager terrain.
FORBID-009: Autoriser un manager à truster un device pending lorsque manager_field_validation_enabled=False.
FORBID-010: Créer un mobile user via signup portail Odoo standard.
FORBID-011: Manager terrain accordant ou retirant mobile_station_user.
FORBID-012: Utiliser system_cooldown pour un device station ou manager.
FORBID-013: Considérer system_cooldown comme autorisation haute valeur.
```

## 0.4 Décisions ouvertes

Aucune décision bloquante ouverte pour la V1.

Les anciennes décisions ouvertes sont clôturées ainsi :

| Ancien ID | Décision V1 |
|---|---|
| OPEN-CLIENT-001 | Volume cible clients mobiles : max 5000. `res.users` par client accepté en V1 avec provisioning contrôlé. |
| OPEN-MANAGER-001 | `manager_field_validation_enabled=False` par défaut. La validation manager trusted est désactivée sauf activation explicite. |


## Additif Patch23D — PIN d'action sensible

INV-PIN-004: une action sensible accepte uniquement le champ `action_code` comme PIN serveur.
FORBID-PIN-001: `action_pin`, `pin` et `secret_code` sont interdits comme alias de confirmation d'action sensible.
FORBID-PIN-002: `secret_code` reste strictement réservé au signup / initialisation du PIN mobile et ne doit jamais être réutilisé comme nom de champ d'action sensible.

<!-- PATCH32B_DEVICE_TRUST_BACKOFFICE_UX_START -->

## Patch32B — Décision : worklist back-office device trust

Patch32B ne transforme pas encore `device_uid` ou `mobile_session_id` en clé d’unicité métier forte.

Décision retenue :

- `acpec.mobile.session` reste un objet de session/token et d’audit.
- La file **Devices à approuver** est une worklist back-office, pas l’historique complet des sessions.
- La déduplication de cette worklist est UX/back-office, pas une contrainte de cycle de vie session.
- Une seule session candidate est conservée par couple `user_id + device_uid`.
- La candidate est la dernière session active du couple, uniquement si elle est encore en `pending_trust`.

Limite assumée : tant que Flutter envoie des valeurs temporaires comme `flutter-android-local`, le backend ne doit pas bâtir une doctrine forte d’identité device sur `device_uid`.

<!-- PATCH32B_DEVICE_TRUST_BACKOFFICE_UX_END -->

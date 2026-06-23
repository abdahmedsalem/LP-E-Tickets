# 08 - Configuration, DEV/PROD, HTTPS et logs

## Portée

Ce module définit la configuration sécurité mobile, les options DEV/PROD, HTTPS, HTTP local et logs/secrets.

Lire avec `00_decisions_invariants.md`.

## 8.1 Table de configuration dédiée

Les paramètres sécurité mobile ne doivent pas être principalement dans `ir.config_parameter`.

Utiliser une table dédiée :

```text
acpec.mobile.security.config
```

Champs recommandés :

```text
application_code
company_id
active

access_token_minutes
refresh_token_days
refresh_grace_seconds

otp_validity_minutes
otp_request_cooldown_seconds
otp_max_attempts
otp_limit_identifier_per_minute
otp_limit_identifier_per_day
otp_limit_device_per_hour
otp_limit_ip_per_hour

pin_required
pin_max_attempts
pin_lockout_minutes
pin_wipe_after_attempts
auto_lock_seconds

dev_fixed_otp_enabled
dev_relax_otp_limits
allow_insecure_http_dev_only

manager_field_validation_enabled
client_device_cooldown_enabled
client_device_cooldown_hours
client_system_cooldown_trust_scope
client_system_cooldown_allows_high_value
max_active_devices_per_user
max_sensitive_role_devices_per_user
max_target_mobile_clients
```

Les changements de config doivent être auditables.

## 8.1.1 Valeurs par défaut V1 tranchées

```text
manager_field_validation_enabled = False
client_device_cooldown_enabled = True
client_device_cooldown_hours = 24
client_system_cooldown_trust_scope = low_value_only
client_system_cooldown_allows_high_value = False
max_active_devices_per_user = 2
max_sensitive_role_devices_per_user = 1
max_target_mobile_clients = 5000
```

Conséquences :

```text
- validation terrain par manager trusted désactivée par défaut ;
- le back-office reste le validateur principal des devices pending et des rôles sensibles ;
- un device client base peut devenir trusted par system_cooldown après délai ;
- ce trust system_cooldown reste limité aux opérations basse valeur ;
- les devices station/manager exigent validation back-office, ou manager trusted borné si option activée pour station seulement ;
- le modèle res.users par client est acceptable jusqu'à 5000 clients mobiles cible.
```

## 8.1.2 Politique de max devices

Définition :

```text
active device = pending_trust ou trusted.
blocked/revoked device = non actif.
```

Politique :

```text
Si active_devices(user) >= max_active_devices_per_user :
    refuser le nouvel enrôlement ou exiger back-office.
    ne jamais auto-truster.
    journaliser device_limit_reached.

Si user a rôle mobile_station_user ou mobile_manager_user
et active_devices(user) >= max_sensitive_role_devices_per_user :
    validation back-office obligatoire.
    manager trusted interdit.
    system_cooldown interdit.
```

## 8.1.3 Source unique de validation device

Les anciens flags séparés du type `new_device_requires_backoffice_validation` ou `new_device_requires_manager_trusted_validation` ne sont pas des sources de vérité V1.

Source de vérité V1 :

```text
manager_field_validation_enabled
client_device_cooldown_enabled
client_device_cooldown_hours
client_system_cooldown_trust_scope
client_system_cooldown_allows_high_value
max_active_devices_per_user
max_sensitive_role_devices_per_user
```

Précédence :

```text
blocked user/device gagne toujours.
max devices dépassé gagne sur cooldown.
rôle station/manager interdit system_cooldown.
manager_field_validation_enabled=False interdit validation manager.
client_system_cooldown_allows_high_value=False bloque haute valeur même si device trusted via system_cooldown.
```

## 8.2 Options frontend

### ODOO_JSONRPC_BASE_URL

DEV :

```text
http://127.0.0.1:8019
```

PROD :

```text
https://api.domaine-client.com
```

### ODOO_USE_ACPEC_AUTH

Active le workflow ACPEC Mobile Auth.

### ACPEC_DEV_FIXED_OTP

Option Flutter de confort. Peut préremplir/suggérer `000000`.

Ne valide jamais l'OTP.

### ACPEC_ALLOW_INSECURE_HTTP

Autorise HTTP uniquement DEV local explicite.

En release/prod, HTTP refusé.

### ODOO_DEBUG_RPC

Logs RPC debug. Ne doit jamais logger secrets.

### ODOO_FUEL_ENABLED

Feature flag métier FuelToken. Pas une option sécurité.

## 8.3 Options backend

### ACPEC_MOBILE_AUTH_DEV_FIXED_OTP

Autorise OTP fixe en DEV.

Interdit en production.

### ACPEC_MOBILE_AUTH_DEV_RELAX_OTP_LIMITS

Assouplit les limites OTP en DEV.

Interdit en production.

## 8.4 HTTP / HTTPS

```text
DEV local contrôlé -> HTTP autorisé explicitement.
PROD / release / environnement réel -> HTTPS obligatoire.
```

Aucune donnée sensible en HTTP production.

## 8.5 Logs et secrets

Jamais loggés :

```text
OTP
PIN
access token
refresh token
secret
clé privée
hash sensible complet
QR sensible complet si évitable
données personnelles inutiles
```

Masquage debug :

```text
otp = ***masked***
pin = ***masked***
access_token = ***masked***
refresh_token = ***masked***
```

## 8.6 Tests minimum

```text
- HTTP autorisé seulement DEV explicite ;
- HTTP refusé release/prod ;
- HTTPS obligatoire PROD ;
- OTP fixe uniquement DEV backend ;
- relax limits uniquement DEV backend ;
- debug logs masquent OTP/PIN/tokens ;
- config change auditée ;
- ir.config_parameter n'est pas source principale de politique sécurité ;
- manager_field_validation_enabled=False bloque validation manager ;
- client_device_cooldown_hours existe et pilote system_cooldown ;
- max_active_devices_per_user dépassé bloque nouvel enrôlement ou impose back-office ;
- flags obsolètes new_device_requires_* absents ou ignorés comme non normatifs.
```

---

## Patch36A - Runtime dev/prod fail-closed

Patch36A remplace la logique historique de relaxation implicite par un gate explicite.

Le mode dev relax est autorise uniquement si:

- ACPEC_ENV, ODOO_ENV ou ENV vaut local, dev ou test;
- ACPEC_FUELTOKEN_DEV_MODE vaut 1.

Regles principales:

- absence de variable runtime = strict / production;
- environnement inconnu = strict + readiness critique;
- ACPEC_FUELTOKEN_TEST_MODE est legacy et ne doit plus activer aucun comportement;
- Odoo --test-enable ne doit jamais ouvrir le dev relax;
- le mode OTP dev accepte 000000 mais ne retourne jamais le code en clair;
- en strict, 000000 est refuse et les limites antiflood a zero reviennent a des valeurs sures;
- acpec_fueltoken_test est une console legacy/dev, pas une source de verite securite.

Document detaille:

refonte_runtime_dev_prod_fail_closed_patch36A.md

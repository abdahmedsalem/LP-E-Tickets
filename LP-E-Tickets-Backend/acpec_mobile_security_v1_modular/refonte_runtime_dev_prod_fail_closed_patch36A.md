# Refonte runtime dev/prod fail-closed - Patch36A

## Statut

Patch backend securite valide sur la branche:

patch36A-backend-runtime-dev-prod-fail-closed

Base avant patch:

73c30d8 merge patch1 frontend qr explicit carnet face line

## Objectif

Patch36A verrouille la separation runtime developpement / production pour:

- acpec_mobile_auth
- acpec_mobile_auth_otp
- acpec_fueltoken_test

La doctrine est fail-closed:

- absence de signal runtime explicite = strict / production;
- environnement inconnu = strict + readiness critique;
- production explicite = strict;
- dev/test/local n'ouvre aucune relaxation sans flag explicite;
- Odoo --test-enable ne doit jamais ouvrir le mode dev relax.

Le seul gate dev autorise est:

ACPEC_ENV ou ODOO_ENV ou ENV = local, dev ou test
+
ACPEC_FUELTOKEN_DEV_MODE = 1

## Decisions de doctrine

### 1. Fin du limbo runtime

Il ne doit plus exister d'etat ambigu ni production ni developpement.

En cas de doute, le runtime est strict.

### 2. Nouveau gate unique

Les decisions de relaxation doivent passer par:

runtime_allows_dev_relax()

et non par une logique du type:

not runtime_is_production()

runtime_is_production() ne doit plus servir de base de decision securite.

### 3. ACPEC_FUELTOKEN_TEST_MODE obsolete

ACPEC_FUELTOKEN_TEST_MODE est conserve uniquement comme signal legacy detecte par readiness.

Il ne doit plus activer:

- OTP dev;
- no-SMS;
- bypass;
- mode console;
- relaxation antiflood;
- debug public.

### 4. Odoo --test-enable

config['test_enable'] ne doit pas ouvrir le dev relax.

Les tests qui veulent simuler le mode dev doivent ouvrir explicitement:

ACPEC_ENV=dev ou ACPEC_ENV=test
ACPEC_FUELTOKEN_DEV_MODE=1

### 5. OTP dev

En mode dev explicite:

- aucun SMS reel n'est envoye;
- le code OTP fixe 000000 est accepte;
- le code OTP n'est jamais retourne publiquement par l'API.

Les champs publics suivants sont supprimes des reponses API:

- otp_dev_code
- dev_otp_code

Ils peuvent rester uniquement dans la redaction defensive de api_common.py.

### 6. Runtime strict

En runtime strict:

- 000000 ne doit pas etre accepte comme OTP;
- un OTP genere aleatoirement ne doit pas etre 000000;
- les valeurs antiflood a zero reviennent a des valeurs sures;
- SMS provider/secrets sont requis si un envoi reel est necessaire;
- aucun debug public sensible ne doit etre expose.

### 7. acpec_fueltoken_test

acpec_fueltoken_test est mis en quarantaine.

Il ne doit plus:

- ecrire des parametres securite dans ir.config_parameter;
- overrider le modele OTP;
- forcer 000000;
- desactiver l'envoi SMS par lui-meme;
- devenir source de verite securite.

Il reste une console legacy/dev pour tester les endpoints reels, disponible seulement si le gate dev explicite est ouvert.

### 8. Parametres persistants

Les parametres securite applicatifs utilisent:

acpec.mobile.security.setting

Les anciens usages ir.config_parameter pour les parametres securite mobiles sont supprimes du runtime.

Les tests de migration legacy peuvent continuer a verifier la migration depuis ir.config_parameter.

## Fichiers runtime principaux

- FuelToken_Backend/addons/acpec_mobile_auth/models/mobile_security_policy.py
- FuelToken_Backend/addons/acpec_mobile_auth/models/mobile_security_readiness.py
- FuelToken_Backend/addons/acpec_mobile_auth/controllers/api_public.py
- FuelToken_Backend/addons/acpec_mobile_auth_otp/controllers/api_otp.py
- FuelToken_Backend/addons/acpec_mobile_auth_otp/models/mobile_auth_otp.py

## Console legacy test

- FuelToken_Backend/addons/acpec_fueltoken_test/hooks.py
- FuelToken_Backend/addons/acpec_fueltoken_test/models/mobile_auth_otp.py
- FuelToken_Backend/addons/acpec_fueltoken_test/tools/test_mode.py
- FuelToken_Backend/addons/acpec_fueltoken_test/data/safe_defaults.xml

## Tests adaptes

- FuelToken_Backend/addons/acpec_mobile_auth/tests/test_mobile_refresh_grace.py
- FuelToken_Backend/addons/acpec_mobile_auth/tests/test_mobile_security_readiness.py
- FuelToken_Backend/addons/acpec_mobile_auth/tests/test_mobile_security_settings_table.py
- FuelToken_Backend/addons/acpec_mobile_auth/tests/test_secret_log_hygiene.py
- FuelToken_Backend/addons/acpec_mobile_auth/tests/test_sensitive_action_pin.py
- FuelToken_Backend/addons/acpec_mobile_auth_otp/tests/test_mobile_pin_reset_otp.py
- FuelToken_Backend/addons/acpec_mobile_auth_otp/tests/test_res_config_settings_security_table.py
- FuelToken_Backend/addons/acpec_mobile_auth_otp/tests/test_sms_gateway.py
- FuelToken_Backend/addons/acpec_fueltoken_test/tests/test_test_mode_hardstop.py

## Validations

Controles statiques:

- python -m py_compile: OK
- git diff --check: OK
- grep securite runtime: OK

Tests cibles:

- acpec_mobile_auth
- acpec_mobile_auth_otp
- acpec_fueltoken_test

Resultat:

66 tests, 0 failed, 0 error.

Test elargi:

- acpec_mobile_auth
- acpec_mobile_auth_otp
- acpec_fueltoken_test
- acpec_fueltoken_api
- acpec_fueltoken_core
- acpec_fueltoken_company
- acpec_fueltoken_purchase

Resultat:

227 tests, 0 failed, 0 error.

## Etat attendu apres commit

Apres commit sur la branche Patch36A:

- HEAD = nouveau commit Patch36A;
- branche = patch36A-backend-runtime-dev-prod-fail-closed;
- main = inchange tant que le merge n'est pas fait;
- origin/main = inchange tant que le push n'est pas fait;
- tag Patch36A = non cree tant que le merge n'est pas fait.

## Suite recommandee

Apres Patch36A, traiter selon priorite:

- code manuel station comme representation alternative du QR actif;
- durcissement concurrency carnet / QR / transfert;
- refonte propre de la console acpec_fueltoken_test en vraie console payload/dev.

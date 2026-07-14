# traceability.md — Couverture invariant → code → test

Relie chaque invariant des doctrines à son implémentation et à son test. C'est l'outil de
couverture : tout INV-* sans ligne, ou sans test, est un trou visible.

## Comment tenir cette table

```text
- Une ligne par invariant testable des doctrines D1, D2, D3.
- Statut : à_implementer | implemente | verifie.
  "verifie" = un test existe, cite l'ID, et passe.
- Mettre à jour à CHAQUE patch (exigence AGENTS.md, définition de "terminé").
- Les conventions (D4, CONV-*) ne sont pas tracées ici : elles se vérifient en revue/lint.
```

## Légende des chemins (à adapter à l'arborescence réelle du nouveau code)

```text
Les chemins ci-dessous sont des CIBLES indicatives pour la refonte. La colonne "Réf.
ancien code" pointe, quand c'est utile, vers l'implémentation actuelle qui satisfait déjà
l'invariant et sert de point de départ — à ne pas recopier aveuglément.
```

---

## D1 — Sécurité (extrait amorcé ; compléter pour tous les INV-S/I/D/T/R/A/O/X, GLB)

| INV | Statut | Fichier code (cible) | Test | Réf. ancien code |
|---|---|---|---|---|
| INV-S1 | implémenté_patch43E1 | acpec_fueltoken_base.res_company (flag société FuelToken unique) | T-S1 | Validé par Patch43E1, tests prod-like cible 241+ tests OK, tag cible security-runtime-v1-20260625-patch43E1 |
| INV-S2 | implémenté_patch43E1 | acpec_fueltoken_base.res_company (index unique partiel sur acpec_fueltoken_enabled) | T-S2 | Validé par Patch43E1, tests prod-like cible 241+ tests OK, tag cible security-runtime-v1-20260625-patch43E1 |
| INV-S3 | implémenté_patch43E1 | acpec_mobile_auth.mobile_security_readiness (readiness critique si zéro ou plusieurs sociétés FuelToken) | T-S3 | Validé par Patch43E1, tests prod-like cible 241+ tests OK, tag cible security-runtime-v1-20260625-patch43E1 |
| INV-S4 | implémenté_patch43E2 | acpec_fueltoken_api runtime (wallet/admin/station/QR bornés à la société FuelToken unique) | T-S4 | Validé par Patch43E2, tests prod-like cible 264+ tests OK, tag cible security-runtime-v1-20260625-patch43E2 |
| INV-S5 | implémenté_patch43E2 | acpec_fueltoken_api runtime (aucun utilisateur hors société FuelToken n’atteint un objet FuelToken) | T-S5 | Validé par Patch43E2, tests prod-like cible 264+ tests OK, tag cible security-runtime-v1-20260625-patch43E2 |
| INV-I1 | vérifié_patch43F2A | acpec_fueltoken_mobile_security.res_users + acpec_mobile_auth readiness (FuelToken mobile: login == mobile_phone == numéro local 8 chiffres) | T-I1-F2A | Validé par Patch43F2A : module dédié FuelToken phone-only, fixtures alignées, tests prod-like 256 tests OK |
| INV-I3 | implémenté_patch43F1 | acpec_mobile_auth.res_users (index unique partiel mobile_only + mobile_phone non vide) | T-I3 | Validé par Patch43F1, tests prod-like cible 270+ tests OK, tag cible security-runtime-v1-20260625-patch43F1 |
| INV-I5 | vérifié_patch43F2A | acpec_fueltoken_mobile_security.res_users + account.request (un mobile FuelToken a exactement un numéro canonique, pas email comme identité) | T-I5-F2A | Validé par Patch43F2A : contraintes write/create FuelToken + demandes signup phone-only, tests prod-like 256 tests OK |
| INV-D4 | implémenté_patch43C | acpec_mobile_auth (single trusted device per user, révocation du trust précédent à la promotion, lock transactionnel, garde défensive non déclarative) | T-D3 | Validé par Patch43C, tests prod-like 233 tests OK, tag cible security-runtime-v1-20260625-patch43C |
| INV-D7 | implémenté_patch43A | acpec_mobile_auth (refus dur device blocked, révocation sessions, access/refresh tokens inutilisables) | T-D6 | Validé par Patch43A tag security-runtime-v1-20260625-patch43A, tests prod-like 228 tests OK |
| INV-D8 | implémenté_patch43B | acpec_mobile_auth + acpec_fueltoken_api (trust wall lecture métier + actions sensibles, sans action_code pour lectures) | T-D7 | Validé par Patch43B, tests prod-like 228 tests OK, tag cible security-runtime-v1-20260625-patch43B |
| INV-A1 | vérifié_patch43H0 | acpec_mobile_auth.controllers.api_common (`_require_sensitive_action_pin`, `_sensitive_action_transaction`) + acpec_fueltoken_api controllers sensibles | TestSensitiveActionPin + TestMobileSecurityAuditLog + TestSensitiveActionPinGate + TestAdminSensitiveInventoryPolicy + tests runtime policy action_code/idempotency | Patch43H0 : action_code obligatoire pour actions sensibles, lectures sans action_code, audit sans PIN brut |
| INV-X3 | implémenté_patch43D | acpec_mobile_auth + acpec_fueltoken_api (audit allowed fail-closed dans la transaction métier, audit refus sécurité committed séparé, helpers explicites) | T-X3a/b/c/d | Validé par Patch43D, tests prod-like cible 238+ tests OK, tag cible security-runtime-v1-20260625-patch43D |
| ... | ... | ... | ... | ... |


### Note Patch43F2A — FuelToken mobile security phone-only

Patch43F2A ajoute `acpec_fueltoken_mobile_security` comme couche dédiée FuelToken, sans casser la généricité de `acpec_mobile_auth`.

Validation :
- branche : `patch43F2A-fueltoken-mobile-security`
- run prod-like : `acpec_mobile_auth,acpec_mobile_auth_otp,acpec_fueltoken_mobile_security,acpec_fueltoken_api`
- résultat : `0 failed, 0 error(s) of 256 tests`
- correction fixtures : les users mobiles FuelToken de test respectent `login == mobile_phone`
- correction collision : `32342008` remplacé par le numéro réservé libre `21000008`
- doctrine confirmée : `res.partner.phone` reste contact, pas identité sécurité

## D2 — Métier (extrait amorcé ; compléter pour tous les INV-W/C/TR/Q/TX/VAL)

| INV | Statut | Fichier code (cible) | Test | Réf. ancien code |
|---|---|---|---|---|
| INV-W1 | vérifié_patch43G3 | acpec_fueltoken_core.models.fuel_wallet (`models.Constraint` unique partner/company + `get_or_create`) | TestD2MechanicalInvariants | Patch43G3 : unicité wallet partner/company prouvée en test |
| INV-C2 | vérifié_patch43G3 | acpec_fueltoken_core.models.fuel_face_line (conservation quantités face) | TestD2MechanicalInvariants | Patch43G3 : conservation `qty_initial == available + active + blocked + consumed + expired` prouvée |
| INV-C6 | vérifié_patch43G6 | purchase → face_line → qr_line → transaction_line + transfert (`purchase_id`, `purchase_line_id`, `face_line_id`) | TestPurchaseLotPropagation | Patch43G6 : propagation origine achat/lot prouvée end-to-end |
| INV-TR1 | vérifié_patch43G1 | acpec_fueltoken_base.models.fuel_carnet_transfer (relocalisation carnet) | tests transfert existants | Audit G1 : transfert relocalise les faces vers wallet destination |
| INV-TR4 | vérifié_patch43G1 | acpec_fueltoken_base.models.fuel_carnet_transfer (`UNIQUE(source_wallet_id, idempotency_key)`) | tests idempotence transfert existants | Audit G1 : replay/conflict couverts |
| INV-TR5 | vérifié_patch43G5 | acpec_fueltoken_core.models.fuel_carnet_transfer (`FOR UPDATE` wallets/face lines + `invalidate_recordset`) | TestCarnetTransferLockReread | Patch43G5 : relecture après verrou prouvée par test dédié |
| INV-Q6 | vérifié_patch43G4 | acpec_fueltoken_core.models.fuel_qr (`action_consume_by_station`, `_lock_records`, double relecture idempotence) | TestConsumeStationGuard, TestConsumeStationConcurrency, TestStationQrUseRuntimePolicy | Patch43G4 : double consommation, idempotence station et verrou FOR UPDATE prouvés |
| INV-Q8 | vérifié_patch43G3 | acpec_fueltoken_core.models.fuel_qr (`models.Constraint` public code/hash + génération aléatoire) | TestD2MechanicalInvariants | Patch43G3 : identifiants QR publics/numériques générés et uniques prouvés |
| INV-TX2 | vérifié_patch43G2 | acpec_fueltoken_core.models.fuel_transaction + transaction lines append-only | TestFuelTransactionAppendOnly | Patch43G2 : `write()` économique et `unlink()` transaction/lines bloqués hors contexte interne |
| INV-VAL1 | vérifié_patch43G8 | acpec.fuel.face.line / acpec.fuel.qr.line (`write` guards + contextes internes contrôlés) | TestEconomicIdentityImmutability + TestQrSeparerRuntimePolicy + run élargi 323 tests | Patch43G8 : identité économique immuable, transitions métier contrôlées, fixtures QR adaptées |
| ... | ... | ... | ... | ... |

## D3 — Mode dev/test (extrait amorcé ; compléter pour tous les INV-DEV, DEV-GLB)

| INV | Statut | Fichier code (cible) | Test | Réf. ancien code |
|---|---|---|---|---|
| INV-DEV-1 | à_implementer | mobile_security_policy.runtime_allows_dev_relax | T-DEV-1..4 | mobile_security_policy.py |
| INV-DEV-8 | à_implementer | (aucun contrôle rouge derrière la porte dev) | T-DEV-8..14 | — |
| INV-DEV-10 | à_implementer | trust uniquement par approbation back-office | T-DEV-16 | mobile_session.py |
| ... | ... | ... | ... | ... |

---

## Synthèse de couverture (à tenir à jour)

```text
Total invariants D1 :  __ / __ verifie
Total invariants D2 :  __ / __ verifie
Total invariants D3 :  __ / __ verifie

Invariants sans test (trous) : [lister ici]
Invariants nouveaux non encore implémentés : préfixes mobiles FuelToken 2/3/4, ... (compléter)
```

## Patch43F2B — contrat signup_identifier strict

Statut : vérifié_patch43F2B.

Date : 2026-06-26.

Objet :
- Renforcement du contrat `signup_identifier` / `signup_identifier_type`.
- `signup_identifier_type` devient un contrat explicite optionnel : `phone` ou `email`.
- Si le type est fourni, il doit correspondre à la valeur transmise.
- Si le type est absent, le backend conserve le fallback automatique contrôlé.
- Pour FuelToken / Tickets Carburant, l'identité mobile reste strictement phone-only.

Doctrine téléphone F2B :
- Téléphone accepté uniquement si `^[234][0-9]{7}$`.
- Exactement 8 chiffres.
- Premier chiffre obligatoirement `2`, `3` ou `4`.
- Aucune normalisation backend de `+222...`, `222...`, espaces ou tirets.
- Les formats internationaux ou nettoyables sont refusés au lieu d'être convertis.

Doctrine `mobile_only` confirmée :
- `mobile_only` est un flag backend `res.users`.
- Le frontend ne décide jamais `mobile_only`.
- Le backend force `mobile_only=True` lors de la création d'un compte mobile via `_create_mobile_signup_account`.
- Les utilisateurs web/back-office restent `mobile_only=False`.
- Les rôles métier FuelToken restent séparés du flag technique `mobile_only`.

Tests validés :
- Test ciblé : `264 tests`, `0 failed`, `0 error`.
- Test élargi avec `acpec_fueltoken_api` : `264 tests`, `0 failed`, `0 error`.
- Nouveaux tests F2B effectivement découverts :
  - `acpec_mobile_auth` passe à `144 tests`.
  - `acpec_fueltoken_mobile_security` passe à `10 tests`.

Cas négatifs couverts :
- `+22223000001`
- `22223000001`
- `0022223000001`
- `2300 0001`
- `23-00-00-01`
- `59000001`
- `70000001`
- `323420056`
- `3475`
- `abdb7374`
- `abdbd@abdc`

Impact invariants :
- INV-I1 renforcé : identité FuelToken phone-only, login/mobile_phone/signup_identifier alignés.
- INV-I5 renforcé : téléphone canonique local strict, sans normalisation implicite.

## Patch43F2C — ownership backend du payload signup

Statut : vérifié_patch43F2C.

Date : 2026-06-26.

Objet :
- Verrouillage par test de la propriété backend des champs sécurité pendant le flux public signup/register OTP.
- Le frontend peut fournir les champs publics nécessaires à l'inscription, mais ne peut pas piloter les champs sécurité du `res.users`.
- Patch volontairement test-only : aucune modification métier, car le code existant construit déjà `user_vals` côté serveur via whitelist.

Doctrine confirmée :
- `mobile_only` est forcé backend.
- `mobile_state` est décidé backend.
- `active`, `login`, `password`, `company_id`, `company_ids`, `groups_id` et rôles mobiles ne sont pas décidés par le frontend.
- Les rôles manager/station/admin restent exclusivement attribués par backend/back-office.
- Le PIN mobile reste `secret_code`, pas le champ `password` éventuellement envoyé par le frontend.

Test ajouté :
- `TestAcpecMobileAuthOtpSms.test_f2c_signup_verify_ignores_frontend_security_fields`.

Payload empoisonné couvert :
- `mobile_only=False`
- `mobile_state='approved'`
- `active=False`
- `login='evil-f2c@example.com'`
- `password='9999'`
- `company_ids` vers une société étrangère
- `groups_id` / `group_ids` avec groupes interdits
- `role='manager'`
- `mobile_profile='manager'`

Résultat attendu verrouillé :
- user final actif.
- `mobile_only=True`.
- `mobile_state='self_registered'`.
- `login == mobile_phone == signup_identifier`.
- société limitée à la société backend.
- aucun groupe interne, manager, station ou admin injecté.
- PIN `1234` accepté.
- PIN/password frontend `9999` refusé.
- demande d'inscription approuvée après OTP, sans attribution de rôles métier.

Tests validés :
- Test ciblé : `265 tests`, `0 failed`, `0 error`.

## Patch43F2D — fondation modèle device mobile générique

Statut : vérifié_patch43F2D.

Date : 2026-06-26.

Objet :
- Création de la fondation générique `acpec.mobile.device` dans `acpec_mobile_auth`.
- Séparation conceptuelle entre device durable et session runtime.
- Le modèle device reste neutre et réutilisable hors FuelToken.
- Aucun rattachement comportemental complet de `acpec.mobile.session` vers `acpec.mobile.device` dans ce patch.

Doctrine validée :
- `acpec_mobile_auth` porte la couche générique mobile : user mobile, OTP/PIN, session, device, trust et audit.
- Pas de module séparé `acpec_mobile_session` en V1.
- FuelToken reste au-dessus et ne contamine pas les modèles session/device génériques.
- Le trust device est défini par couple `user_id + stable_device_uid`, pas globalement par UID device.
- Une session reste un objet runtime temporaire ; le device devient un objet durable.

Modèle ajouté :
- `acpec.mobile.device`.

Contraintes et garanties :
- unicité `UNIQUE(user_id, stable_device_uid)`.
- rejet des UID instables ou placeholders : `flutter-android-local`, `flutter-ios-local`, `flutter-web-local`, `web-local`.
- un seul device `trusted` par utilisateur.
- approuver un nouveau device remet les autres devices trusted du même user en `pending_trust`.
- le même `stable_device_uid` pour un autre user reste indépendant.

Back-office :
- vues list/form/search pour les devices mobiles.
- menu `Devices mobiles` sous `Mobile Auth / Opérations`.
- actions génériques : trust, block, reset trust.

Tests ajoutés :
- `TestMobileDeviceModel.test_f2d_mobile_device_can_be_created_for_mobile_user`.
- `TestMobileDeviceModel.test_f2d_mobile_device_unique_per_user_and_stable_uid`.
- `TestMobileDeviceModel.test_f2d_mobile_device_rejects_unstable_device_uid`.
- `TestMobileDeviceModel.test_f2d_trusting_device_resets_other_trusted_devices_for_same_user`.
- `TestMobileDeviceModel.test_f2d_trusting_same_stable_uid_for_other_user_does_not_reset_first_user`.
- `TestMobileDeviceModel.test_f2d_mobile_device_rejects_ambiguous_bulk_trust_for_same_user`.
- `TestMobileDeviceModel.test_f2d_mobile_device_views_and_action_exist`.

Limites volontaires :
- pas encore de champ `device_id` sur `acpec.mobile.session`.
- pas de migration des sessions existantes.
- pas de modification de `create_for_user`, `refresh_with_token` ou des actions session existantes.
- pas de changement FuelToken.

Suite prévue :
- Patch43F2E : rattacher `acpec.mobile.session` à `acpec.mobile.device`.
- Patch43F2F : verrouiller le lifecycle téléphone / device / session.

## Patch43F2E — signup uses Odoo user partner delegation

Statut : vérifié_patch43F2E.

Date : 2026-06-26.

Objet :
- Nettoyage du flux signup mobile autour de `res.users` / `res.partner`.
- Le signup mobile ne crée plus explicitement un `res.partner` avant le `res.users`.
- Le signup crée le `res.users` directement et utilise `user.partner_id` comme partenaire métier.
- Le partenaire du user devient le propriétaire métier naturel des futurs objets FuelToken.

Doctrine validée :
- `res.users` = compte technique mobile, authentification, sécurité, sessions et devices.
- `res.partner` = identité métier et propriétaire des objets économiques FuelToken.
- `1 user = 1 partner`, conforme au modèle Odoo.
- Le signup ne renseigne pas `partner.phone`.
- Le signup ne renseigne pas `partner.email`.
- L'enrichissement commercial du partenaire se fait par back-office.
- Le signup renseigne seulement `partner.ref = MOB:<mobile_phone>` pour tracer l'origine mobile canonique.
- Le signup marque `partner.acpec_is_mobile_partner = True` pour filtrer les partenaires mobiles.
- Les users mobiles restent filtrables par `res.users.mobile_only = True`.

Filtres ajoutés :
- Utilisateurs mobiles : `res.users.mobile_only = True`.
- Partenaires mobiles : `res.partner.acpec_is_mobile_partner = True`.

Test ajouté :
- `TestAcpecMobileAuthOtpSms.test_f2e_signup_uses_odoo_user_partner_delegation_without_contact_enrichment`.

Résultat attendu :
- `account_request.partner_id == user.partner_id`.
- `user.login == user.mobile_phone == signup_identifier`.
- `partner.ref == MOB:<mobile_phone>`.
- `partner.acpec_is_mobile_partner is True`.
- `partner.phone` et `partner.email` restent vides au signup.
- L'email éventuel reste porté par la demande d'inscription, pas par le partenaire.

### Patch43F2G — ancien workflow de changement de téléphone mobile

Statut : obsolète et retiré par Patch43M23-C0.

Doctrine actuelle :
- Le téléphone est l’identité mobile FuelToken canonique.
- Une identité mobile établie est immuable.
- Aucun changement de téléphone n’est autorisé par le BO, le mobile, une API, un wizard ou une action serveur.
- L’écriture directe de `login` ou `acpec_mobile_phone` reste refusée.
- La méthode historique `action_fueltoken_change_mobile_phone()` est conservée uniquement pour refuser explicitement toute tentative.
- Le nettoyage défensif des anciennes actions Odoo dangereuses reste actif.
- Le modèle `acpec.fueltoken.mobile.phone.change.log`, son ACL, ses vues, son action et son menu sont retirés du code.
- Patch43M23-C0 n’exécute aucune migration ni conversion des anciennes données.
- Un nouveau numéro implique le blocage de l’ancienne identité puis la création contrôlée d’une nouvelle identité distincte.

Tests :
- `test_mobile_partner_technical_identity.py` vérifie que le changement de téléphone est refusé.
- `test_mobile_phone_change_action_cleanup.py` vérifie la suppression des anciennes actions dangereuses.
- `test_mobile_phone_change_removed_c0.py` vérifie que le modèle obsolète n’est plus enregistré et que la méthode de refus reste disponible.

### Patch43F2H0 — alignement doctrine device durable et user blocked

Statut : doctrine alignée, runtime user blocked à implémenter dans F2I.

Décisions doctrine :
- `acpec.mobile.device` est l'objet durable du couple `(user_id, device_uid stable)`.
- Les sessions mobiles référencent le device durable ; elles ne portent pas seules la confiance.
- INV-D11 ajouté : user mobile blocked persistant refuse OTP/login sur tout appareil.
- INV-D12 ajouté : réactivation user blocked ne restaure jamais automatiquement le trust device.
- RES-3 ajouté : pas de gel wallet séparé en V1 ; la valeur est protégée par la pile d'accès.
- Modèle de menace M2/M3 synchronisé avec INV-D7 et INV-D11 : vol device, SIM-swap, blocage device et blocage user persistant.
- PIN/action_code et idempotence restent obligatoires pour les actions sensibles et mutations économiques, mais hors périmètre F2H.
- F2H reste limité au remplacement device normal ; F2I portera perte/vol/suspicion et user blocked.

Tests à venir :
- T-D9 et T-D10 à couvrir dans F2I.
- F2H couvrira remplacement device normal : nouveau device pending, approbation BO, ancien device non trusted.

### Patch43F2H — couverture remplacement device normal

Statut : test de cycle device replacement normal validé, sans changement runtime.

Décisions confirmées :
- F2H couvre le remplacement normal d'appareil : même user, même numéro, même partner.
- Un nouveau device naît en `pending_trust` et n'accède à aucune donnée métier.
- L'approbation BO du nouveau device le passe en `trusted`.
- L'ancien device trusted repasse en `pending_trust`.
- L'ancienne session peut rester active et candidate BO tant que le device est pending, mais l'accès métier est refusé par le backend.
- Aucun rôle station/manager n'est injecté ; le rôle FuelToken client reste le seul rôle métier ajouté au trust device.
- F2H ne traite pas perte/vol/SIM-swap/user blocked ; ces cas restent F2I.
- Aucun gel wallet séparé n'est introduit.

Tests :
- `test_mobile_device_replacement_lifecycle.py`
- Run ciblé : `TestMobileDeviceReplacementLifecycle`, 0 failed, 0 error.

### Patch43F2I — user blocked OTP/login lifecycle

Statut : INV-D11/T-D9 couverts côté OTP/session, patch minimal.

Décisions confirmées :
- `mobile_state='blocked'` est un état user persistant.
- Un user mobile blocked est refusé à la demande OTP login/reset avant création de challenge.
- Un OTP déjà émis n'est pas consommé si le user devient blocked avant vérification.
- Aucune session mobile n'est ouverte pour un user blocked.
- Les sessions actives sont déjà révoquées quand le user passe hors `approved/self_registered`.
- La réactivation user ne modifie pas automatiquement les états devices : trusted reste trusted, pending reste pending_trust, blocked reste blocked.
- F2I ne crée pas de gel wallet séparé.
- F2I ne traite ni la création d’une nouvelle identité après changement réel de numéro, ni le retour vers un ancien device.

Tests :
- `test_mobile_user_blocked_otp.py`
- `test_mobile_user_blocking_lifecycle.py`
- Run ciblé : `TestMobileUserBlockedOtp` + `TestMobileUserBlockingLifecycle`, 0 failed, 0 error.

### Patch43F2J — ancienne composition téléphone et device

Statut : scénario obsolète, non présent dans le runtime actuel.

Doctrine actuelle :
- Une identité mobile FuelToken établie est immuable.
- Le remplacement normal d’un device ne modifie jamais `login`, `acpec_mobile_phone`, `user_id` ou `partner_id`.
- Un changement réel de numéro implique le blocage de l’ancienne identité puis la création contrôlée d’une nouvelle identité distincte.
- Il n’existe aucun workflow combinant mutation du téléphone et remplacement du device.
- Aucun test runtime F2J n’est conservé, car ce scénario n’est plus autorisé.
- Les tests de remplacement de device restent applicables uniquement à identité mobile inchangée.

### Patch43F2K — ancien device retrouvé / retour vers ancien device

Statut : composition F2H validée par tests, sans changement runtime.

Décisions confirmées :
- F2K ne crée aucun mécanisme parallèle.
- Un ancien device retrouvé en `pending_trust` peut être ré-approuvé normalement par BO.
- La ré-approbation de l'ancien device le remet `trusted`.
- Le device précédemment trusted redescend en `pending_trust`.
- La règle un seul device trusted par user reste l'unique règle métier.
- Le user reste le même, le téléphone reste le même, le partner/wallet/carnets restent conservés.
- Un relogin depuis le device retrouvé réutilise le device durable existant et récupère son trust.
- F2K ne couvre pas un device `blocked`.
- Device blocked / user blocked / perte suspecte / vol / SIM-swap restent des cas F2I ou procédure BO spécifique hors F2K normal.

Tests :
- `test_mobile_old_device_return_lifecycle.py`
- Run ciblé : `TestMobileOldDeviceReturnLifecycle`, 0 failed, 0 error.

### Patch43F2L — BO user blocking lifecycle simple

Statut : actions BO simples blocage/réactivation user mobile, avec warning wizard et trace chatter, sans modèle métier de log dédié.

Décisions confirmées :
- F2L ajoute deux actions BO : bloquer utilisateur mobile et réactiver utilisateur mobile.
- Le blocage user passe `mobile_state` à `blocked`.
- La réactivation user repasse par défaut à `self_registered`, ou `approved` si explicitement demandé.
- Le motif est obligatoire.
- Le wizard affiche un avertissement avant confirmation.
- La trace est postée dans le chatter du partner lié au user mobile.
- Aucun modèle métier de log supplémentaire n'est créé.
- Les sessions actives sont révoquées par la logique existante quand le user sort de `approved/self_registered`.
- Les devices ne sont pas modifiés automatiquement.
- Réactivation user ne restaure aucune session et n'approuve aucun device.
- Blocage user reste distinct du blocage device.

Tests :
- `test_mobile_user_blocking_backoffice.py`
- Run ciblé : `TestMobileUserBlockingBackofficeLifecycle`, 0 failed, 0 error.

### Patch43F2M — BO device menu visibility

Statut : exposition BO des devices durables, patch UI/navigation uniquement.

Décisions confirmées :
- F2M ne modifie pas le runtime device.
- Le modèle durable `acpec.mobile.device` existait déjà.
- L'action `acpec_mobile_auth.action_acpec_mobile_device` existait déjà.
- Les boutons device existaient déjà : approuver, bloquer, remettre en attente.
- Le problème était l'exposition dans le BO FuelToken après réorganisation/override du menu Mobile Auth.
- F2M ajoute un menu visible `Devices mobiles — audit`.
- Le menu ouvre les devices durables, pas seulement les sessions candidates.
- `Devices à approuver` reste la file opérationnelle des sessions candidates.
- Les boutons de la fiche device sont francisés : Approuver le device, Bloquer le device, Remettre en attente.
- Aucun déblocage device direct vers trusted n'est ajouté.

Tests :
- `test_mobile_device_menu_backoffice.py`
- Run ciblé : `TestMobileDeviceBackofficeMenu`, 0 failed, 0 error.

### Patch43F2N — BO device trust action hardening

Statut : durcissement BO des actions sensibles device, avec wizard, motif obligatoire et interdiction du retour direct blocked -> trusted.

Décisions confirmées :
- F2N ne change pas le contrat API mobile.
- Les actions device restent portées par `acpec.mobile.device` et déléguées depuis `acpec.mobile.session`.
- `action_trust_device()` refuse désormais un device déjà `blocked`.
- `action_trust_device()` refuse aussi l'approbation d'un device si le user mobile est `blocked`.
- Le bouton BO d'approbation n'est visible que pour les devices `pending_trust`.
- Le blocage device BO passe par un wizard de confirmation avec motif obligatoire.
- La remise en attente device BO passe par un wizard de confirmation avec motif obligatoire.
- `blocked -> pending_trust` reste possible, mais seulement avec motif ; l'approbation `trusted` doit être faite séparément.
- `blocked -> trusted` direct est interdit.
- Le blocage device remplit `blocked_reason`.
- Les motifs sont tracés dans le chatter du device.
- Aucun nouveau modèle métier de log n'est ajouté.
- Les sessions actives liées à un device bloqué restent révoquées par la logique existante `_sync_sessions_from_device()`.

Tests :
- `TestMobileDeviceTrustHardening`, 0 failed, 0 error.
- `TestMobileDeviceTrustBackoffice`, 0 failed, 0 error.
- `TestMobileDeviceBackofficeMenu`, 0 failed, 0 error.

### Patch43F2O — pending trust endpoint guard audit

Statut : test-only / traceability, sans changement runtime.

Décisions confirmées :
- `pending_trust` est un état runtime du device, pas un état métier du user.
- `pending_trust` ne retire pas les groupes FuelToken du user mobile.
- Les groupes FuelToken indiquent le rôle métier théorique du compte.
- Le trust device indique si ce téléphone peut agir maintenant.
- Un user peut donc garder `group_fuel_user`, `group_fuel_station` ou `group_fuel_manager` pendant que le device courant est `pending_trust`.
- Les endpoints métier doivent rester protégés par `_require_trusted_mobile_auth()` ou par une action sensible qui l'appelle.
- Un device `pending_trust` peut seulement accéder aux flux minimaux auth/session/profil nécessaires pour afficher son état d'approbation.
- Un device `pending_trust` ne doit pas lire wallet/station/admin ni manipuler tickets/carnets/QR.

Tests ajoutés :
- `TestPendingTrustEndpointGuardAudit`
- Vérifie qu'un client `pending_trust` garde `group_fuel_user` mais ne lit pas le wallet.
- Vérifie qu'une station `pending_trust` garde `group_fuel_station` mais ne lit pas le profil station.
- Vérifie qu'un manager `pending_trust` garde `group_fuel_manager` mais ne lit pas les données admin.

### Patch43G1 — business invariant traceability audit

Statut : audit-only / traceability, sans changement runtime.

Objet :
- Relecture des invariants D2 encore marqués `à_implementer` dans `traceability.md`.
- Extraction large des modèles, contraintes, verrous, idempotences, QR identifiers et tests métier FuelToken.
- Classification des invariants D2 entre déjà implémenté, vérifié, test manquant, preuve manquante et vrai trou runtime.

Résultat d'audit D2 :
- `INV-W1` : implémenté par contrainte wallet unique `(partner_id, company_id)` et logique `get_or_create`, mais test direct à ajouter.
- `INV-C2` : implémenté par conservation des quantités face, mais test direct à ajouter.
- `INV-C6` : propagation lot/purchase observée, mais preuve end-to-end à renforcer.
- `INV-TR1` : transfert/relocalisation déjà couvert par les tests transfert existants.
- `INV-TR4` : idempotence transfert déjà couverte par contrainte unique et tests replay/conflict.
- `INV-TR5` : verrouillage/relecture observés, mais test de concurrence ou preuve dédiée à ajouter.
- `INV-Q6` : consommation QR verrouillée observée, mais test double-consommation à renforcer.
- `INV-Q8` : identifiants QR aléatoires/uniques observés, mais test direct à ajouter.
- `INV-TX2` : partiel ; prochain vrai patch runtime recommandé, car l'append-only transaction/transaction lines doit être durci.
- `INV-VAL1` : trop transverse ; à prouver après fermeture des invariants mécaniques.

Décision :
- Ne pas patcher le runtime en G1.
- Fermer G1 comme audit documentaire.
- Ouvrir ensuite `Patch43G2 — transaction append-only hardening` pour `INV-TX2`.

Tests :
- Aucun test Odoo requis pour G1, car aucun code runtime n'est modifié.
- Validation attendue : `git diff --check` et revue de `traceability.md`.

### Patch43G2 — transaction append-only hardening

Statut : runtime hardening + tests.

Objet :
- Fermer `INV-TX2`, identifié par G1 comme partiel.
- Rendre les transactions Tickets Carburant réellement append-only côté ORM.
- Protéger aussi les lignes `acpec.fuel.transaction.line`, pas seulement l'en-tête transaction.

Changements :
- `acpec.fuel.transaction.write()` conserve l'autorisation de modification de `note` seule hors contexte interne.
- `acpec.fuel.transaction.write()` bloque les modifications économiques hors contexte `allow_fuel_transaction_update`.
- `acpec.fuel.transaction.unlink()` est interdit hors contexte interne `allow_fuel_transaction_unlink`.
- `acpec.fuel.transaction.line.write()` est interdit hors contexte interne `allow_fuel_transaction_update`.
- `acpec.fuel.transaction.line.unlink()` est interdit hors contexte interne `allow_fuel_transaction_unlink`.
- Le cleanup du test concurrence station utilise le contexte interne d'unlink transaction.
- Les fixtures station concurrence sont réalignées avec la doctrine mobile test : `login == mobile_phone == 21xxxxxx`.

Doctrine :
- Une transaction FuelToken est un journal append-only.
- Une ligne de transaction FuelToken est également append-only.
- Les exceptions internes sont réservées aux flux techniques contrôlés : enrichissement interne, cleanup test, maintenance/migration explicite.

Tests :
- Ciblé `TestFuelTransactionAppendOnly` : 4 tests, 0 échec, 0 erreur.
- Élargi après correction fixture concurrence : 306 tests, 0 échec, 0 erreur.

### Patch43G3 — D2 mechanical invariant tests

Statut : test-only, sans changement runtime.

Objet :
- Fermer les preuves directes des invariants D2 mécaniques identifiés par G1.
- Prouver `INV-W1`, `INV-C2` et `INV-Q8` par tests dédiés.
- Conserver la terminologie Odoo 19 : contraintes déclarées via `models.Constraint`, pas `_sql_constraints`.

Invariants couverts :
- `INV-W1` : unicité wallet par `(partner_id, company_id)` et idempotence `get_or_create`.
- `INV-C2` : conservation des quantités de face.
- `INV-Q8` : génération et unicité des identifiants QR publics et numériques.

Tests :
- Ciblé `TestD2MechanicalInvariants` : 3 tests, 0 échec, 0 erreur.
- Élargi core : 129 tests, 0 échec, 0 erreur.
- Élargi sécurité/runtime : 319 tests, 0 échec, 0 erreur.

Décision :
- `INV-W1`, `INV-C2` et `INV-Q8` passent en `vérifié_patch43G3`.
- Aucun changement runtime nécessaire.

### Patch43G4 — QR consume lock/idempotency proof

Statut : audit/traceability-only, sans changement runtime.

Objet :
- Fermer `INV-Q6` par preuve des tests existants.
- Vérifier que la consommation station d'un QR est verrouillée, idempotente et non rejouable économiquement.
- Ne pas ajouter de runtime : le mécanisme existe déjà dans `action_consume_by_station`.

Preuves runtime :
- `action_consume_by_station()` recherche une transaction existante par `transaction_type`, `qr_id` et `idempotency_key` avant verrou.
- La méthode prend un verrou pessimiste sur le QR via `_lock_records()` / `SELECT ... FOR UPDATE`.
- La méthode relit le QR après verrou avec `invalidate_recordset()`.
- La méthode revérifie l'idempotence après verrou avant tout effet économique.
- Une deuxième consommation non idempotente est refusée par l'état `consumed`.
- Un rejeu idempotent retourne la transaction existante sans ré-encaisser.
- Une concurrence réelle est sérialisée par le verrou QR.

Tests existants utilisés comme preuve :
- `TestConsumeStationGuard.test_double_consume_is_blocked_by_state`
- `TestConsumeStationGuard.test_consume_is_idempotent_on_key`
- `TestConsumeStationGuard.test_cross_company_consume_is_blocked`
- `TestConsumeStationConcurrency.test_concurrent_consume_is_serialized_and_spends_once`
- `TestStationQrUseRuntimePolicy.test_station_qr_use_replays_same_payload_for_same_idempotency_key`
- `TestStationQrUseRuntimePolicy.test_station_qr_use_rejects_same_key_with_different_payload`
- `TestStationQrUseRuntimePolicy.test_station_qr_use_requires_idempotency_key`
- `TestStationQrUseRuntimePolicy.test_station_qr_use_requires_trusted_device`

Décision :
- `INV-Q6` passe en `vérifié_patch43G4`.
- Aucun changement runtime nécessaire.
- Aucun nouveau test nécessaire, car la preuve existe déjà dans les tests core/concurrence/API station.

### Patch43G5 — carnet transfer lock/re-read proof

Statut : test-only, sans changement runtime.

Objet :
- Fermer `INV-TR5`, identifié par G1 comme implémenté mais sans preuve dédiée.
- Prouver que le transfert de carnet relit l'état réel des lignes après verrou avant confirmation.
- Ne pas modifier le runtime : le verrouillage `FOR UPDATE` et `invalidate_recordset()` existent déjà.

Preuve ajoutée :
- `TestCarnetTransferLockReread.test_g5_transfer_rereads_locked_face_line_before_confirming`
- Le test charge volontairement le cache ORM de la face line.
- Le test modifie ensuite `wallet_id` hors ORM par SQL direct pour simuler un état concurrent/stale.
- `action_confirm()` doit relire après verrou et refuser le transfert, au lieu de confirmer avec un cache obsolète.
- Le transfert reste en `draft` et la face line reste dans le wallet externe simulé.

Tests :
- Ciblé `TestCarnetTransferLockReread` : 1 test, 0 échec, 0 erreur.
- Élargi sécurité/runtime : 320 tests, 0 échec, 0 erreur.

Décision :
- `INV-TR5` passe en `vérifié_patch43G5`.
- Aucun changement runtime nécessaire.

### Patch43G6 — purchase/lot propagation end-to-end proof

Statut : test-only, sans changement runtime.

Objet :
- Fermer `INV-C6`, identifié par G1 comme implémenté probable mais sans preuve end-to-end.
- Prouver que l'origine achat/lot est conservée de bout en bout.
- Couvrir achat, face line, QR line, transaction line, consommation station et transfert de carnet.

Preuve ajoutée :
- `TestPurchaseLotPropagation.test_g6_purchase_origin_is_preserved_through_qr_consume_and_transfer`

Chaîne prouvée :
- `purchase` → `face_line` : conservation `purchase_id` et `purchase_line_id`.
- `face_line` → `qr_line` : conservation `face_line_id`, `purchase_id`, `purchase_line_id`.
- `qr_line` → transaction émission QR : conservation origine achat/lot.
- consommation station : transaction line conserve `purchase_id`, `purchase_line_id`, `face_line_id`, `qr_id`, `qr_line_id`.
- transfert carnet : la même `face_line` est déplacée vers le wallet destination sans recréer l'origine.
- transactions de transfert source/destination conservent `purchase_id`, `purchase_line_id`, `face_line_id` et `transfer_id`.

Tests :
- Ciblé `TestPurchaseLotPropagation` : 1 test, 0 échec, 0 erreur.
- Élargi sécurité/runtime : 321 tests, 0 échec, 0 erreur.

Décision :
- `INV-C6` passe en `vérifié_patch43G6`.
- Aucun changement runtime nécessaire.

### Patch43G7 — VAL1 doctrine/audit

Statut : doctrine/traceability-only, sans changement runtime.

Objet :
- Clarifier `INV-VAL1` avant tout durcissement runtime.
- Éviter de traiter "conservation valeur transverse" comme un invariant comptable faux ou trop large.
- Distinguer les invariants déjà vérifiés des protections encore manquantes.

Constat :
- `INV-C2` couvre déjà la conservation des quantités d'une face line entre statuts.
- `INV-C6` couvre déjà la propagation end-to-end de l'origine achat/lot.
- `INV-Q6` couvre déjà la consommation QR verrouillée et idempotente.
- `INV-TR5` couvre déjà la relecture après verrou lors du transfert.
- `INV-TX2` couvre déjà le caractère append-only des transactions.
- Les transactions FuelToken sont un journal d'audit métier, pas une balance comptable débit/crédit.

Doctrine VAL1 retenue :
- La valeur économique d'un Ticket est conservée par identité immuable + transitions d'état tracées.
- La valeur faciale et l'origine achat/lot ne doivent pas changer après création.
- Les QR lines et transaction lines doivent hériter cette identité économique.
- Les transitions de quantité doivent passer par les flux contrôlés.
- Le wallet est une projection calculée des face lines, pas une source autonome de vérité.

Champs sensibles à durcir ensuite :
- `acpec.fuel.face.line` : `purchase_id`, `purchase_line_id`, `carnet_type_id`, `face_value`, `qty_initial`, `lot_short_code`, `carnet_short_code`, `carnet_sequence`.
- `acpec.fuel.qr.line` : `face_line_id`, `purchase_id`, `purchase_line_id`, `face_value`, `qty`.

Décision :
- `INV-VAL1` ne passe pas en `vérifié` avec G7.
- `INV-VAL1` passe en `clarifié_patch43G7_a_durcir_patch43G8`.
- Le prochain patch recommandé est `Patch43G8 — economic identity immutability`.

### Patch43G8 — economic identity immutability

Statut : runtime + tests.

Objet :
- Fermer `INV-VAL1` après clarification doctrinale G7.
- Empêcher les mutations directes des champs d'identité économique.
- Préserver les flux métier contrôlés : achat, émission QR, retrait/séparation QR, expiration, consommation station, transfert carnet.

Durcissement ajouté :
- `acpec.fuel.face.line.write()` bloque les écritures directes sur :
  - `purchase_id`, `purchase_line_id`, `carnet_type_id`, `face_value`, `qty_initial`,
    `carnet_no`, `lot_short_code`, `carnet_short_code`, `carnet_sequence`.
  - `wallet_id`, `qty_available`, `qty_qr_active`, `qty_qr_blocked`, `qty_consumed`, `qty_expired`
    hors contexte interne contrôlé.
- `acpec.fuel.qr.line.write()` bloque les écritures directes sur :
  - `source_qr_line_id`, `face_line_id`, `purchase_id`, `purchase_line_id`, `face_value`, `expires_at`.
  - `qr_id`, `qty`, `state` hors contexte interne contrôlé.
- `acpec.fuel.qr.line.unlink()` est interdit hors contexte interne explicite.

Contextes internes :
- `allow_fuel_face_line_state_update`
- `allow_fuel_face_line_economic_update`
- `allow_fuel_qr_line_state_update`
- `allow_fuel_qr_line_economic_update`
- `allow_fuel_qr_line_unlink`

Tests ajoutés :
- `TestEconomicIdentityImmutability.test_g8_face_line_direct_economic_mutations_are_blocked_but_transfer_flow_works`
- `TestEconomicIdentityImmutability.test_g8_qr_line_direct_economic_mutations_are_blocked_but_split_flow_works`

Corrections de fixtures :
- `TestQrSeparerRuntimePolicy` adapte les écritures artificielles de `expires_at` avec contexte interne,
  car `expires_at` est maintenant protégé par G8.

Tests :
- Ciblé `TestEconomicIdentityImmutability` : 2 tests, 0 échec, 0 erreur.
- Ciblé `TestQrSeparerRuntimePolicy` : 5 tests, 0 échec, 0 erreur.
- Élargi sécurité/runtime : 323 tests, 0 échec, 0 erreur.

Décision :
- `INV-VAL1` passe en `vérifié_patch43G8`.
- La conservation de valeur transverse est portée par :
  - identité économique immuable,
  - transitions de quantité contrôlées,
  - origine achat/lot propagée,
  - transactions append-only,
  - wallet comme projection des face lines.

## Patch43H1 - Invariants runtime H0C/H0D/H0E

| Invariant | Statut | Code | Test | Note |
|---|---|---|---|---|
| INV-H0C-MANAGER-POSITIVE-VALIDATOR | implémenté_patch43H0C | `acpec_fueltoken_api.controllers.api_admin.AcpecFuelTokenAdminApi`; `_raise_mobile_manager_backoffice_only`; inventaire fermé des endpoints manager mobile | `test_admin_sensitive_inventory_policy.py`; `test_mobile_security_runtime_docs.py`; tests runtime admin carnet/station/purchase/device | Validé H0C, ciblé API 144 tests OK puis H0E cible 153 tests OK. |
| INV-H0D-PURCHASE-APPROVAL-PARTNER-TRUSTED-ACCESS | implémenté_patch43H0D | `AcpecFuelTokenAdminApi._require_purchase_partner_trusted_mobile_access_for_manager_api`; `purchase_approve` API-only | `test_admin_purchase_runtime_policy.py`; `test_mobile_security_runtime_docs.py` | Back-office et `purchase.action_approve()` restent inchangés. Validé H0D, cible API 146 tests OK. |
| INV-H0E-CLIENT-WALLET-OPERATIONAL-ROLE-SEGREGATION | implémenté_patch43H0E | `acpec.fuel.wallet` helpers `_fueltoken_partner_has_non_empty_client_wallet`, `_assert_no_non_empty_client_wallet_for_operational_mobile_user`, `_assert_users_have_no_non_empty_client_wallet_for_operational_mobile_role`; `fuel_station._validate_station_mobile_user`; `mobile_session_device_trust.action_trust_device`; `res.users` create/write guard | `test_client_wallet_operational_role_segregation.py`; `test_mobile_security_runtime_docs.py` | Validé H0E, cible API 153 tests OK et run élargi 318 tests OK. |
| CHK-H0E1-NO-BACKUP-ARTIFACTS | vérifié_patch43H0E1 | repository hygiene; aucun `*.bak_patch43H0C/H0D/H0E` versionné ou présent sous `addons` | commande audit `find addons -name "*.bak_patch43H0E*" -o -name "*.bak_patch43H0D*" -o -name "*.bak_patch43H0C*"` | Cleanup commit `43142e1`, tag `security-runtime-v1-20260627-patch43H0E1`. |

## Patch43H2 - Contrat API manager mobile

| Invariant | Statut | Code | Test | Note |
|---|---|---|---|---|
| INV-H2-MANAGER-MOBILE-API-CONTRACT | vérifié_patch43H2 | `acpec_fueltoken_api.controllers.api_admin.AcpecFuelTokenAdminApi`; endpoints `purchases_pending`, `purchase_detail`, `purchase_approve`, `stations_list`, `devices_pending_trust`, `device_approve_pending_trust`; helpers pagination/idempotency/company scope dans `api_common.py` | `test_admin_manager_api_contract.py`; complète `test_admin_sensitive_inventory_policy.py`, `test_sensitive_device_trust_gate.py`, `test_admin_purchase_runtime_policy.py` | H2 verrouille le contrat API manager mobile sans changement runtime. |

<!-- PATCH43H5_SECURITY_ERROR_HARDENING_START -->

## Patch43H5 — Durcissement des erreurs mobiles sensibles

### Doctrine

La série Patch43H5 sépare deux familles d’erreurs mobiles :

- erreurs techniques inattendues : réponse publique `SERVER_ERROR`, référence `ERR-*`, marqueur BO agrégé ;
- refus sensibles attendus : code public générique, message public générique, référence `SEC-*`, audit backend détaillé.

Règle centrale :

- Flutter ne reçoit pas la cause sensible détaillée ;
- le backend conserve la cause exacte dans l’audit ou le marqueur technique ;
- les secrets, OTP, PIN, action codes, QR brut, payloads sensibles et traces techniques ne sont pas exposés au mobile.

### Patch43H5A — Erreurs techniques API mobile

Tag : `security-runtime-v1-20260628-patch43H5A`

Commit final : `36b7d7c patch43H5A document UI and dev language convention`

Contenu :

- modèle BO `acpec.mobile.api.error.marker` ;
- agrégation par fingerprint ;
- réponse publique `SERVER_ERROR` avec référence `ERR-*` ;
- logs serveur redacted ;
- pas de traceback/payload/header/token/OTP/PIN/action_code/QR brut en base ;
- ACL réservée aux auditeurs sécurité mobile ;
- purge cron.

Tests validés : `352 tests, 0 failed, 0 error`.

### Patch43H5B — Refus sensibles publics

Tag : `security-runtime-v1-20260628-patch43H5B`

Commit final : `48a0a24 merge patch43H5B mobile sensitive public error hardening`

Contenu :

- références `SEC-*` pour les refus sensibles attendus ;
- champ `reference` dans l’audit sécurité mobile ;
- séparation public/backend : code public générique côté Flutter, `debug_reason` détaillé côté backend ;
- durcissement des familles `AUTH_REFUSED`, `RATE_LIMITED`, `DEVICE_NOT_ALLOWED`, `ACTION_REFUSED`, `QR_NOT_USABLE`, `TRANSFER_REFUSED`, `FORBIDDEN`, `REQUEST_REFUSED`, `SIGNUP_NOT_ALLOWED` ;
- `idempotency_conflict` exposé comme `REQUEST_REFUSED + SEC-*` ;
- QR station sensible exposé comme `QR_NOT_USABLE + SEC-*` ;
- validations de forme utiles conservées en `VALIDATION_ERROR`.

Tests validés : `354 tests, 0 failed, 0 error`.

Nettoyage volontaire associé :

- `FuelToken_Backend/Dockerfile`
- `FuelToken_Backend/addons/acpec_api_tests.txt`
- `FuelToken_Backend/addons/docker-compose.yml`
- `FuelToken_Backend/addons/odoo.conf`

### Patch43H5C1 — OTP dev-mode prod guard

Tag : `security-runtime-v1-20260628-patch43H5C1`

Commit final : `43ce4aa merge patch43H5C1 otp devmode prod guard test`

Doctrine confirmée :

- le code OTP dev fixe `000000` est conservé ;
- le mode relax dev est conservé ;
- l’anti-flood OTP peut être désactivé en dev relax ;
- le relax dev exige runtime dev-like + `ACPEC_FUELTOKEN_DEV_MODE` ;
- en prod, même avec `ACPEC_FUELTOKEN_DEV_MODE=1`, le runtime reste strict.

Test ajouté :

- `test_dev_fixed_otp_code_is_rejected_when_runtime_switches_to_prod`

Tests validés : `355 tests, 0 failed, 0 error`.

### Patch43H5C2 — RATE_LIMITED public backend

Tag : `security-runtime-v1-20260628-patch43H5C2`

Commit final : `e0e819a merge patch43H5C2 backend rate limited public hardening`

Contenu :

- `MobileAuthRateLimitError` reste une exception interne modèle ;
- le message interne modèle reste `Trop de demandes OTP. Veuillez réessayer plus tard.` ;
- la sortie publique API devient `RATE_LIMITED` avec message générique `Trop de tentatives. Réessayez plus tard.` ;
- ajout d’une référence `SEC-*` ;
- audit backend avec `debug_reason = auth_rate_limited` et `audit_code = RATE_LIMITED` ;
- latence minimale auth/OTP appliquée via `started_at` ;
- routes concernées : `request-otp`, `verify-otp`, `signup` ;
- test route mis à jour avec numéro mobile de test `21...` ;
- aucun nouveau `ir.config_parameter` n’est ajouté pour les settings sécurité mobile.

Tests validés :

- run ciblé auth/OTP : `338 tests, 0 failed, 0 error`
- run complet : `355 tests, 0 failed, 0 error`

### Points ouverts

#### OPEN-H5C-FLUTTER-001 — Shape de `request_otp`

Le backend conserve deux formes publiques :

- compte connu : `challenge_id`, `challenge_ref`, `expires_at`, `delivery` ;
- compte inconnu login/reset : message générique sans `challenge_id`.

Ce point peut rester un oracle de forme. Il doit être repris côté Flutter/API contract, pas dans H5C2 backend.

#### OPEN-H5C-SIGNUP-LATENCY-001 — Refus signup non-rate-limit

H5C2 applique la latence aux rate-limits publics. Les refus signup/register non-rate-limit restent à analyser séparément si un durcissement timing plus strict est requis.

### État final

Dernier état confirmé :

- `main == origin/main == origin/HEAD == e0e819affb94ae72da913836ebdb7a7e60cc5068`
- tag `security-runtime-v1-20260628-patch43H5C2` sur HEAD

La série H5A à H5C2 est close côté backend pour les erreurs techniques `ERR-*`, les refus sensibles `SEC-*`, le prod guard OTP dev-mode, et le rate-limit public backend.

<!-- PATCH43H5_SECURITY_ERROR_HARDENING_END -->


---

## Patch43H5G — Doctrine des sources de configuration sécurité mobile

Date : 2026-06-28
Type : documentation / doctrine uniquement
Runtime : aucun changement
Tests Docker : non requis

### Objectif

Ce patch fixe la doctrine de classification des paramètres liés à la sécurité mobile avant de poursuivre l’alignement Flutter/API.

Il ne modifie pas le code runtime, ne migre aucun paramètre et ne change pas le comportement existant.
Les écarts constatés sont documentés comme points ouverts, à traiter plus tard seulement s’ils deviennent une faille majeure ou une décision V2 explicite.

### Doctrine retenue

Les sources de configuration sont classées en trois familles.

#### 1. Variables d’environnement / configuration de déploiement

À utiliser pour :

- identité runtime : production, développement, test ;
- secrets techniques ;
- clés, tokens et credentials externes ;
- paramètres qui doivent être portés par le déploiement et non par un administrateur fonctionnel Odoo ;
- garde-fous qui ne doivent pas être modifiables depuis la base.

Exemples attendus :

```text
ACPEC_ENV
ODOO_ENV
ENV
ACPEC_FUELTOKEN_DEV_MODE
ACPEC_FUELTOKEN_TEST_MODE uniquement comme signal legacy/test à détecter
SMS_TOKEN / SMS_VALIDATION_KEY cible doctrinale future
secrets de dérivation / secrets techniques
```

Règle : la classification prod/dev/test ne doit pas dépendre de `ir.config_parameter`.

#### 2. Modèle applicatif `acpec.mobile.security.setting`

À utiliser pour les politiques de sécurité mobile applicatives auditées et contrôlées :

- durées token/session ;
- PIN mobile ;
- tentatives et verrouillage ;
- OTP expiration / longueur / tentatives ;
- rate-limit / antiflood ;
- seuils de readiness applicative ;
- paramètres sécurité mobiles qui doivent être visibles, contrôlés et testables dans le back-office sécurité.

Règle : les décisions de sécurité mobile applicative ne doivent pas être ajoutées directement dans `ir.config_parameter`.

#### 3. `ir.config_parameter`

À réserver à :

- paramètres Odoo génériques ou historiques ;
- compatibilité legacy ;
- paramètres UI non critiques ;
- paramètres fonctionnels non sensibles ;
- source de migration vers `acpec.mobile.security.setting` lorsque nécessaire.

Règle : `ir.config_parameter` ne doit pas devenir la source de vérité des politiques de sécurité mobile sensibles.

### État actuel constaté

#### Runtime prod/dev/test

L’état actuel est conforme à la doctrine.

Le runtime s’appuie sur :

```text
ACPEC_ENV
ODOO_ENV
ENV
odoo.tools.config seulement comme fallback de déploiement
```

Il ne s’appuie pas sur `ir.config_parameter` pour classifier production / développement / test.

Décision V1 : garder.

#### Dev relax / OTP dev mode

Le relax dev reste conditionné par :

```text
runtime dev-like
ACPEC_FUELTOKEN_DEV_MODE
```

Le setting legacy `acpec_mobile_auth.otp_dev_mode` peut encore exister dans la table de settings sécurité, mais il ne doit pas redevenir une source runtime en production.

Décision V1 : garder le comportement actuel.
Action future éventuelle : maintenir uniquement l’alerte readiness si un legacy setting dangereux reste activé.

#### Paramètres sécurité mobile numériques

Les paramètres comme :

```text
access_token_minutes
refresh_token_days
refresh_token_grace_seconds
mobile_pin_lock_seconds
mobile_pin_max_attempts
mobile_pin_hard_block_attempts
otp_code_length
otp_expiration_minutes
otp_max_attempts
otp_request_cooldown_seconds
otp_limit_identifier_per_minute
otp_limit_identifier_per_day
otp_limit_ip_per_hour
otp_limit_register_ip_per_day
```

sont portés par `acpec.mobile.security.setting`.

Décision V1 : conforme, garder.

#### Migration legacy depuis `ir.config_parameter`

La migration legacy vers `acpec.mobile.security.setting` est acceptable si elle reste :

- contrôlée ;
- non destructive ;
- limitée à la reprise d’anciens paramètres ;
- sans faire de `ir.config_parameter` une source runtime prioritaire pour les politiques sensibles.

Décision V1 : garder.

#### Paramètres UI non critiques

Les paramètres de couleur / compatibilité UI peuvent rester dans `ir.config_parameter`.

Exemples :

```text
acpec_mobile_auth.color_brand_light
acpec_mobile_auth.color_primary_light
```

Décision V1 : garder.

#### Paramètres fonctionnels hors sécurité mobile auth

Certains paramètres fonctionnels, par exemple une limite de taille de preuve d’achat, peuvent rester dans `ir.config_parameter` s’ils ne pilotent pas une décision de sécurité mobile auth.

Décision V1 : garder, à documenter si nécessaire dans le module concerné.

### Point ouvert principal : SMS gateway

L’état actuel SMS est volontairement documenté comme legacy / ambigu.

Constat actuel :

```text
sms_gateway runtime lit encore SMS_* depuis ir.config_parameter puis env.
readiness production vérifie surtout les variables env.
res.config.settings écrit encore des paramètres SMS_* dans ir.config_parameter.
des tests existants verrouillent encore ce comportement historique.
```

Paramètres concernés :

```text
SMS_PROVIDER
SMS_VALIDATION_KEY
SMS_TOKEN
SMS_URL
SMS_DEFAULT_LANG
```

Doctrine cible probable :

```text
SMS_PROVIDER      : non secret, peut être app setting ou ICP encadré
SMS_URL           : non secret relatif, peut être app setting ou ICP encadré
SMS_DEFAULT_LANG  : non secret, peut rester ICP/app setting
SMS_VALIDATION_KEY: secret, cible env/config
SMS_TOKEN         : secret, cible env/config
```

Décision V1 :

```text
Ne pas migrer SMS_* maintenant.
Ne pas modifier sms_gateway runtime.
Ne pas modifier res.config.settings.
Ne pas casser les tests existants.
Classer le sujet comme OPEN-H5G-SMS-001.
```

Justification :

- le comportement est historique et couvert par tests ;
- le modifier avant Flutter peut créer un risque opérationnel SMS ;
- aucune preuve actuelle ne montre une exposition publique directe des secrets SMS ;
- le sujet est important mais relève plutôt d’un durcissement V2 ou d’une décision dédiée.

Critère de réouverture immédiate en V1 :

```text
- secret SMS exposé publiquement ;
- secret SMS loggé en clair ;
- utilisateur non autorisé pouvant lire/modifier SMS_TOKEN ou SMS_VALIDATION_KEY ;
- readiness production donnant un feu vert alors que les secrets sont absents ou incohérents ;
- usage SMS permettant un bypass OTP ou une dégradation fail-open.
```

### Points ouverts

#### OPEN-H5G-SMS-001 — Séparer secrets SMS et paramètres non secrets

Décider plus tard si :

- les secrets SMS doivent devenir env-only ;
- les champs SMS secrets doivent être retirés de `res.config.settings` ;
- les paramètres non secrets SMS doivent rester ICP ou migrer vers un modèle applicatif ;
- les tests historiques doivent être adaptés.

Statut V1 : ouvert, non bloquant.

#### OPEN-H5G-ICP-LEGACY-001 — Nettoyage legacy `ir.config_parameter`

Inventorier plus tard les anciens paramètres ICP migrés vers `acpec.mobile.security.setting` et décider s’ils doivent être conservés, ignorés, masqués ou supprimés.

Statut V1 : ouvert, non bloquant.

#### OPEN-H5G-QR-SECRET-001 — Revue séparée des secrets QR numériques

Certains secrets de dérivation QR relèvent de la configuration de déploiement et non des settings sécurité mobile.
Ce sujet ne doit pas être mélangé avec la doctrine des settings mobile auth.

Statut V1 : ouvert, hors périmètre H5G.

#### OPEN-H5H-DOCTRINE-CODE-ALIGNMENT — Revue doctrine/code globale

Après H5G, faire une revue séparée d’alignement doctrine ↔ code ↔ tests sur :

```text
runtime prod/dev/test
OTP dev-mode
rate-limit / latence
erreurs publiques ERR-* / SEC-*
audit BO
device trust
rôles mobiles
signup/register
readiness fail-closed
```

Statut : prochaine étape avant Flutter.

### Décision finale H5G

Pour la V1 :

```text
Aucun changement runtime.
Aucune migration SMS.
Aucun changement Flutter.
Aucun changement de settings existants.
La doctrine est fixée.
Les écarts non critiques sont documentés en OPEN.
```

Avocat du diable :

Le point SMS/ICP n’est pas ignoré. Il est reconnu comme une dette de doctrine potentiellement importante.
Mais le traiter maintenant sans preuve de faille majeure risquerait de détourner la stabilisation V1 et de casser un comportement opérationnel couvert par tests.


---

## Patch43H5G2 — Alignement documentaire canonique doc_refonte

Statut : doc-only.

Objet :
- correction des chemins canoniques dans `AGENTS.md` ;
- clarification dans `00_index.md` que les références D5/D6 sont historiques ou
  optionnelles si absentes du dossier canonique ;
- élévation de la doctrine H5G des sources de configuration dans
  `DOCTRINE_MODE_DEV_TEST_FUELTOKEN_V1.md` §6 ;
- conservation de `OPEN-H5G-SMS-001` comme dette documentée non bloquante V1.

Décision :
- aucune modification runtime ;
- aucun changement de tests ;
- aucun changement SMS/ICP ;
- aucun changement Flutter.

---

## Patch43H5H — Revue alignement doctrine / code / tests backend

Date : 2026-06-28
Type : documentation / revue uniquement
Runtime : aucun changement
Tests Docker : non requis

### Objectif

Patch43H5H documente la revue d'alignement entre :

```text
doctrine canonique doc_refonte
code backend actuel
tests backend existants
```

Cette revue est faite avant l'alignement Flutter/API public error contract.

Elle ne modifie aucun runtime, aucun test, aucun XML, aucun ACL, aucun setting et aucun flux Flutter.

### Verdict H5H

Aucune faille majeure V1 n'a été identifiée dans le backend actuel.

Le backend est globalement aligné avec la doctrine canonique sur les axes suivants :

```text
runtime prod/dev/test
OTP dev-mode / prod guard
rate-limit / latence
erreurs publiques ERR-* / SEC-*
audit BO
device trust
rôles mobiles
signup/register
readiness fail-closed
settings source doctrine
```

Décision :

```text
Aucun patch runtime requis avant Flutter.
Aucun changement SMS/ICP en V1.
Aucun changement device trust.
Aucun changement signup/register.
Aucun changement de contrat backend avant extraction Flutter.
```

### Matrice doctrine / code / tests

```text
Axe                              Code actuel / tests                              Écart                    Décision
Runtime prod/dev/test             env + config fallback, pas ICP                  aucun                    garder
OTP dev-mode / prod guard         relax uniquement runtime dev-like/env           aucun                    garder
Legacy otp_dev_mode DB            readiness signale, pas source runtime           aucun                    garder
Rate-limit / antiflood            fail-closed prod, zéro seulement dev relax      aucun                    garder
Latence refus sensibles           min latency sur refus sensibles H5E             aucun bloquant           garder
Erreurs techniques                SERVER_ERROR + ERR-* + marker BO                aucun                    garder
Refus sensibles                   SEC-* + message générique + audit détaillé      aucun                    garder
Audit BO SEC                      reference/public_message/debug_reason + ACL     aucun                    garder
Device trust                      nouveau device pending_trust                    aucun                    garder
TOFU                              absent                                          conforme doctrine        garder absent
Rôles mobiles                     pas choisis par mobile, BO only                 aucun                    garder
Signup/register                   refus sensibles génériques, session contrôlée   aucun                    garder
Validation formulaire signup      NAME_REQUIRED/SECRET_CODE_* publics             choix H5E validé         garder
Readiness fail-closed             prod guards + alertes legacy                    aucun majeur            garder
Settings source doctrine          H5G/H5G2 documentés, SMS/ICP ouvert             dette connue            garder ouvert
```

### Points non bloquants identifiés

#### OPEN-H5H-PUBLIC-LATENCY-SETTING-001 — Configuration de `public_auth_min_latency_ms`

Constat :

```text
Le code peut lire acpec_mobile_auth.public_auth_min_latency_ms via
acpec.mobile.security.setting, avec défaut sécurisé.
La clé n'est pas nécessairement exposée comme setting BO canonique.
```

Impact :

```text
Non bloquant V1.
Le défaut prod reste strict.
Le dev relax peut garder une latence nulle selon doctrine dev/test.
```

Décision V1 :

```text
Ne pas modifier le runtime maintenant.
```

Options futures :

```text
- ajouter explicitement la clé aux settings BO si on veut la rendre pilotable ;
- ou documenter qu'elle reste un réglage interne caché avec défaut sécurisé.
```

Statut : ouvert, non bloquant.

#### OPEN-H5H-WEB-GUARD-001 — Clarifier le fail-open contrôlé du web session guard

Constat :

```text
Le guard web qui bloque les comptes mobile_only en session web Odoo bloque sur
détection positive, mais peut fail-open si la détection elle-même échoue.
```

Avocat du diable :

```text
Cela peut sembler contredire la doctrine fail-closed.
```

Clarification V1 :

```text
Le fail-closed strict s'applique aux décisions de sécurité mobile/API.
Le web session guard est une défense en profondeur autour des requêtes web Odoo.
Il ne doit pas faire tomber tout Odoo si sa détection auxiliaire échoue.
```

Décision V1 :

```text
Pas de changement runtime.
Documenter comme exception auxiliaire contrôlée.
```

Statut : ouvert, non bloquant.

### Points déjà documentés et maintenus ouverts

#### OPEN-H5G-SMS-001 — SMS / ICP

Le sujet SMS/ICP reste tel que documenté par H5G/H5G2 :

```text
SMS runtime peut encore lire certains paramètres depuis ir.config_parameter.
La cible doctrinale future des secrets SMS est env/config.
Le comportement historique n'est pas migré en V1.
```

Critères de réouverture V1 inchangés :

```text
- secret SMS exposé publiquement ;
- secret SMS loggé en clair ;
- utilisateur non autorisé pouvant lire/modifier SMS_TOKEN ou SMS_VALIDATION_KEY ;
- readiness production donnant un feu vert malgré secrets absents ou incohérents ;
- usage SMS permettant un bypass OTP ou une dégradation fail-open.
```

Statut : ouvert, non bloquant V1.

### Décision finale H5H

```text
La revue doctrine/code/tests backend est faite.
Aucun écart backend ne bloque le passage à Flutter.
Les points ouverts sont documentaires ou V2 sauf preuve de faille majeure.
```

Prochaine étape :

```text
Flutter/API public error contract alignment.
```

### Patch43H7 — mobile user blocked public API code

Statut : implémenté_patch43H7.

Date : 2026-06-29.

Objet :
- Ajout du code public explicite `MOBILE_USER_BLOCKED` pour les refus API/session liés à `mobile_state='blocked'`.
- Migration Odoo 19 de la contrainte SQL de `acpec.mobile.api.error.marker` depuis `_sql_constraints` vers `models.Constraint(...)` afin de supprimer le warning registry.
- Le lifecycle user blocked existait déjà : refus OTP/login, absence de session pour user blocked, révocation des sessions actives et réactivation sans restauration automatique du trust device.
- H7 ne modifie pas ce lifecycle ; il renforce seulement le contrat d’erreur API public.
- Les flux publics OTP/signup restent protégés contre l’énumération : `request-otp` / `verify-otp` ne deviennent pas des oracles publics de compte bloqué.

Doctrine confirmée :
- `MOBILE_USER_BLOCKED` concerne le compte mobile (`res.users.mobile_state='blocked'`).
- `DEVICE_BLOCKED` concerne l’appareil durable / session device.
- `MOBILE_USER_BLOCKED` ne doit pas être traité comme session expirée.
- `MOBILE_USER_BLOCKED` doit être routé côté mobile vers un écran compte bloqué ou message compte bloqué, distinct de l’écran appareil bloqué.

Tests :
- `test_mobile_user_blocked_public_code.py`.
- Couvre l’enregistrement du code public, la détection du message `Compte mobile bloqué.`, et la non-exposition dans les flux OTP publics.

Impact invariants :
- INV-D11 renforcé côté contrat API public.
- INV-D12 inchangé : la réactivation user ne restaure pas automatiquement le trust device.

### Patch43H8 — public QR name and carnet short code format

Statut : implémenté_patch43H8.

Date : 2026-06-29.

Objet :
- Le champ `name` de `acpec.fuel.qr` prend désormais le code QR numérique public au format `NNNN-NNNN-NNNN`.
- `carnet_short_code` devient un code court public aléatoire au format `AANNNN`.
- `carnet_no` reste inchangé et conserve son rôle de référence complète / traçabilité interne.
- Les anciens carnets ne sont pas migrés dans ce patch ; la règle s’applique aux nouvelles générations.
- `lot_short_code` reste conservé pour tri, audit et regroupement lot, mais n’est plus concaténé dans `carnet_short_code`.

Doctrine confirmée :
- Le code court affiché mobile est `carnet_short_code`, pas `carnet_no`.
- Pas de format public `C001` / `C0001` pour `carnet_short_code`.
- Le code QR manuel numérique reste le contrat station `qr_numeric_code`.

Tests :
- `test_public_qr_carnet_short_code_format.py`.
- Couvre le format `AANNNN`, l’absence de `C001`, et l’abandon de la séquence QR visible dans `qr.name`.

<!-- PATCH43M24D_RPC_REFACTOR_TRACE_BEGIN -->
---

## Patch43M24-D — Doctrine et roadmap de refonte RPC ACPEC

```text
Statut          : doctrine définie — runtime non modifié
Type            : documentation uniquement
Baseline        : b827fc3
Documents       : A1 + A1-R
Patch suivant   : marqueur `_acpec_rpc` strictement additif
```

Objet :

- fixer l’architecture `Flutter ↔ Dio ↔ wrapper ↔ contrôleur ↔ Odoo` ;
- définir les responsabilités de chaque couche ;
- définir le futur `AcpecRpcError` et `@acpec_rpc_endpoint` ;
- préserver M24-C comme frontière terminale ;
- définir le contrat `_acpec_rpc` version 1 ;
- distinguer HTTP, JSON-RPC et payload ACPEC ;
- isoler PIN, session et OTP ;
- publier une roadmap route par route.

État initial des invariants :

| Invariant | Statut | Cible de preuve |
|---|---|---|
| INV-RPC-001 à INV-RPC-005 | doctrine_définie | primitives wrapper + contrôleur pilote |
| INV-RPC-006 | partiellement_prouvé_M24-C | tests wrapper vers M24-C |
| INV-RPC-007 | partiellement_prouvé_M24-B/M24-C | tests propagation concurrence wrapper |
| INV-RPC-008 à INV-RPC-009 | doctrine_définie | tests savepoint / absence commit |
| INV-RPC-010 à INV-RPC-013 | doctrine_définie | marker additif + Flutter fallback |
| INV-RPC-014 | doctrine_définie | série actions sensibles PIN |
| INV-RPC-015 | doctrine_définie | série OTP/SMS |
| INV-RPC-016 | partiellement_prouvé_M24-C | tests logs/secrets élargis |
| INV-RPC-017 | actif_par_roadmap | revue de chaque patch |
| INV-RPC-018 | doctrine_existante_renforcée | serializers et gardes références publiques |

Décision :

```text
Aucun changement runtime dans M24-D.
Le patch marqueur devient M24-E.
Le wrapper complet devient M24-F ou patch ultérieur dédié.
Flutter ne devient pas strict avant émission backend du marqueur.
OTP/SMS reste la dernière famille migrée.
```
<!-- PATCH43M24D_RPC_REFACTOR_TRACE_END -->

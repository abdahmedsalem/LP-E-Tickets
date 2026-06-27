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
| INV-A1 | à_implementer | api_common._require_sensitive_action_pin | T-A1 | api_common.py |
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
| INV-W1 | implémenté_patch43G1_test_direct_manquant | acpec_fueltoken_base.models.fuel_wallet (`UNIQUE(partner_id, company_id)` + `get_or_create`) | T-W1 à ajouter | Audit G1 : implémenté, preuve test directe manquante |
| INV-C2 | implémenté_patch43G1_test_direct_manquant | acpec_fueltoken_base.models.fuel_face_line (conservation quantités face) | T-C2 à ajouter | Audit G1 : contrainte métier présente, test direct à ajouter |
| INV-C6 | implémenté_probable_patch43G1_preuve_end_to_end_manquante | purchase/face/QR/transaction lines (`purchase_id`, `purchase_line_id`) | T-C4 à renforcer | Audit G1 : propagation présente, preuve end-to-end à ajouter |
| INV-TR1 | vérifié_patch43G1 | acpec_fueltoken_base.models.fuel_carnet_transfer (relocalisation carnet) | tests transfert existants | Audit G1 : transfert relocalise les faces vers wallet destination |
| INV-TR4 | vérifié_patch43G1 | acpec_fueltoken_base.models.fuel_carnet_transfer (`UNIQUE(source_wallet_id, idempotency_key)`) | tests idempotence transfert existants | Audit G1 : replay/conflict couverts |
| INV-TR5 | implémenté_patch43G1_test_concurrence_manquant | acpec_fueltoken_base.models.fuel_carnet_transfer (`FOR UPDATE`, relecture/invalidate) | T-TR5 à ajouter/renforcer | Audit G1 : verrouillage observé, preuve test dédiée manquante |
| INV-Q6 | implémenté_patch43G1_test_double_consommation_a_renforcer | acpec_fueltoken_base.models.fuel_qr (`_lock_records`, consommation station) | T-Q5/T-Q7 à renforcer | Audit G1 : verrouillage observé, test double-consommation à renforcer |
| INV-Q8 | implémenté_patch43G1_test_direct_manquant | acpec_fueltoken_base.models.fuel_qr (`public_code`, numeric code hash unique) | T-Q8 à ajouter | Audit G1 : génération aléatoire/unique observée, test direct manquant |
| INV-TX2 | partiel_patch43G1_a_durcir_patch43G2 | acpec_fueltoken_base.models.fuel_transaction + transaction lines | T-TX2 à créer | Audit G1 : `write()` partiellement protégé, `unlink()` transaction/lines à durcir |
| INV-VAL1 | à_prouver_patch43G1 | transverse wallet/faces/QR/transfert/transaction | T-VAL1 à concevoir | Audit G1 : invariant trop large, à traiter après invariants mécaniques |
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

### Patch43F2G — changement téléphone mobile FuelToken contrôlé BO

Statut : implémenté et testé.

Couverture doctrine :
- INV-I7 : changement de numéro exclusivement via back-office contrôlé.
- Même `res.users.id` conservé.
- Même `partner_id` conservé.
- `login` et `mobile_phone` changent ensemble vers le nouveau numéro canonique.
- Écriture directe de `login` / `mobile_phone` refusée pour une identité FuelToken établie.
- Doublon `login` / `mobile_phone` refusé.
- `partner.ref` automatique `MOB:<old_phone>` remplacée par `MOB:<new_phone>`.
- Référence partenaire manuelle conservée.
- Audit créé dans `acpec.fueltoken.mobile.phone.change.log`.
- Log d'audit en lecture seule pour l'admin mobile.
- Sessions actives révoquées systématiquement.
- Trust device conservé : la révocation porte sur les sessions, pas sur le device.
- Wizard back-office disponible depuis la fiche utilisateur.
- Historique disponible dans Configuration > Historique changements téléphone mobile.
- Menu Utilisateurs mobiles — audit filtré par `mobile_only=True`.

Tests :
- `test_mobile_phone_change_lifecycle.py`
- Run complet : 284 tests, 0 failed, 0 error.
- Run ciblé après ACL : 122 tests, 0 failed, 0 error.

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
- F2I ne traite pas changement téléphone + device ni ancien device retrouvé.

Tests :
- `test_mobile_user_blocked_otp.py`
- `test_mobile_user_blocking_lifecycle.py`
- Run ciblé : `TestMobileUserBlockedOtp` + `TestMobileUserBlockingLifecycle`, 0 failed, 0 error.

### Patch43F2J — composition changement téléphone + remplacement device

Statut : composition F2G + F2H validée par tests, sans changement runtime.

Décisions confirmées :
- F2J n'introduit aucun mécanisme parallèle.
- Si téléphone puis device : F2G change `login/mobile_phone`, conserve `user_id/partner_id`, révoque les sessions ; F2H ajoute ensuite le nouveau device `pending_trust` puis `trusted` après approbation BO.
- Si device puis téléphone : F2H approuve le nouveau device et repasse l'ancien en `pending_trust` ; F2G change ensuite le numéro et révoque les sessions sans modifier le trust durable du device.
- L'ancien numéro ne résout plus aucun utilisateur mobile après changement téléphone.
- Le user reste le même, le partner reste le même, le wallet/carnets restent attachés au partner.
- F2J ne traite pas perte/vol/SIM-swap/user blocked ; ces cas restent couverts par F2I.
- F2J ne traite pas ancien device retrouvé ; ce sera F2K si nécessaire.

Tests :
- `test_mobile_phone_device_composition_lifecycle.py`
- Run ciblé : `TestMobilePhoneDeviceCompositionLifecycle`, 0 failed, 0 error.

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

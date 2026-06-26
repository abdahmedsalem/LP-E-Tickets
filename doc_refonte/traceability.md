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
| INV-W1 | à_implementer | fuel_wallet (UNIQUE partner_id, company_id) | T-W1 | fuel_wallet.py |
| INV-C2 | à_implementer | fuel_face_line (conservation des faces) | T-C2 | fuel_face_line.py |
| INV-C6 | à_implementer | propagation lot d'origine | T-C4 | fuel_* (purchase_id) |
| INV-TR1 | à_implementer | fuel_carnet_transfer (relocalisation) | T-TR1 | fuel_carnet_transfer.py |
| INV-TR4 | à_implementer | fuel_carnet_transfer (UNIQUE wallet,idemp.) | T-TR4 | fuel_carnet_transfer.py |
| INV-TR5 | à_implementer | fuel_carnet_transfer (verrou + relecture) | T-TR5 | fuel_carnet_transfer.py |
| INV-Q6 | à_implementer | fuel_qr (consommation verrouillée) | T-Q5,T-Q7 | fuel_qr.py |
| INV-Q8 | à_implementer | fuel_qr (identifiant aléatoire) | T-Q8 | fuel_qr public_code |
| INV-TX2 | à_implementer | fuel_transaction (ajout seul) | T-TX2 | fuel_transaction.py |
| INV-VAL1 | à_implementer | transverse (conservation valeur) | T-VAL1 | (à prouver) |
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
Invariants nouveaux non encore implémentés : INV-I7, préfixes mobiles FuelToken 2/3/4, contrat signup_identifier_type explicite/fallback F2B, ... (compléter)
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

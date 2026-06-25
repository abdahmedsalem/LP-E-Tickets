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
| INV-S2 | à_implementer | res_company (index unique partiel) | T-S1, T-S2 | (nouveau) |
| INV-S3 | à_implementer | mobile_security_readiness | T-S3 | mobile_security_readiness.py |
| INV-I3 | à_implementer | res_users (contrainte unique mobile_phone) | T-I1 | (absente aujourd'hui) |
| INV-D4 | à_implementer | mobile_session (révocation à la promotion) | T-D3 | (nouveau) |
| INV-D7 | implémenté_patch43A | acpec_mobile_auth (refus dur device blocked, révocation sessions, access/refresh tokens inutilisables) | T-D6 | Validé par Patch43A tag security-runtime-v1-20260625-patch43A, tests prod-like 228 tests OK |
| INV-D8 | implémenté_patch43B | acpec_mobile_auth + acpec_fueltoken_api (trust wall lecture métier + actions sensibles, sans action_code pour lectures) | T-D7 | Validé par Patch43B, tests prod-like 228 tests OK, tag cible security-runtime-v1-20260625-patch43B |
| INV-A1 | à_implementer | api_common._require_sensitive_action_pin | T-A1 | api_common.py |
| INV-X3 | à_implementer | audit transactionnel actions autorisées | T-X3 | (best-effort aujourd'hui) |
| ... | ... | ... | ... | ... |

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
Invariants nouveaux non encore implémentés : INV-S2, INV-D4, INV-X3, ... (compléter)
```

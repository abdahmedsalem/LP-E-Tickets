# 00_index — Référentiel doctrinaire ACPEC FuelToken

Point d'entrée unique. Lire ce fichier avant toute tâche. Il dit quoi lire, quand, et
qui gagne en cas de conflit.

```text
---
referentiel: acpec-fueltoken
version: 1.0
statut: actif
ordre_priorite_conflit: [securite > metier > conventions > UX > dev]
principe_global: fail-closed ; en cas de doute, demander ou refuser
---
```

## Documents

### Doctrines canoniques (autorité au niveau invariant)

```text
D1  DOCTRINE_SECURITE_MOBILE_FUELTOKEN_V1.md
    Portée : identité, société, appareil/confiance, session, inscription, actions
    sensibles, OTP, prérequis transverses. Préfixes : INV-S/I/D/T/R/A/O/X, GLB.

D2  DOCTRINE_METIER_FUELTOKEN_V1.md
    Portée : wallet, carnet, transfert, QR, transaction, conservation de la valeur.
    Préfixes : INV-W/C/TR/Q/TX/VAL.

D3  DOCTRINE_MODE_DEV_TEST_FUELTOKEN_V1.md
    Portée : porte unique dev, liste blanche/rouge, simulation d'états vs relaxation.
    Préfixes : INV-DEV, DEV-GLB.

D4  CONVENTIONS_DEVELOPPEMENT_ACPEC.md
    Portée : lisibilité, nommage, langue, métadonnées modules, UI, versions Odoo,
    méthode de travail de l'agent. Préfixes : CONV-LIS/NOM/LANG/MOD/UI/VER/WORK.
```

### Références historiques d'implémentation (subordonnées, non obligatoires)

```text
D5  refonte_runtime_dev_prod_fail_closed_patch36A.md
    Référence historique Patch36A sur la classification d'environnement et la porte
    fail-closed. Si ce fichier n'est pas présent dans doc_refonte, D3 fait foi.

D6  PATCH42C_SIGNUP_DEVICE_SESSION_DOCTRINE.md
    Référence historique Patch42C sur l'inscription, le contrat public, les helpers
    et account.request. Si ce fichier n'est pas présent dans doc_refonte, D1 §4 fait foi.

H5G Doctrine des sources de configuration sécurité mobile
    Source canonique : D3 §6.
    État constaté, dette SMS/ICP et OPEN associés : traceability.md, section Patch43H5G.
```

## Résolution de conflit

```text
1. Une doctrine canonique (D1-D4) prime sur une référence historique ou un document d'implémentation (D5-D6).
2. Entre canoniques, l'ordre est : securite > metier > conventions > UX > dev.
   Exemple : si une facilité dev (D3) contredit un contrôle de sécurité (D1), D1 gagne.
3. Une référence historique ou un document d'implémentation ne peut jamais autoriser ce qu'une canonique interdit.
4. En cas de doute non tranché par ces règles : demander, ne pas supposer.
```

## Doctrines applicables par type de tâche

```text
Inscription / OTP / session          => D1 (§1,§3,§4,§6), D3, D6 si présent
Confiance d'appareil / approbation   => D1 (§2), D3
Transfert de carnet                  => D2 (§3,§6), D1 (§5)
Émission / consommation de QR        => D2 (§4,§6), D1 (§5)
Wallet / carnet / conservation       => D2 (§1,§2,§5,§6)
Mode dev / configuration runtime     => D3 (§1), D5 si présent
Sources settings sécurité mobile     => D3 (§6), traceability.md Patch43H5G
Tout patch, sans exception           => D4 (conventions) + AGENTS.md (protocole)
```

## Couverture

La table `traceability.md` relie chaque INV-* à son code et à son test. Tout invariant
sans ligne dans la table est un trou de couverture. La maintenir à chaque patch.

## Points ouverts à trancher

```text
- Orthographe du site dans les manifestes : "apcec" vs "acpec" (D4, en-tête).
- Version exacte d'Odoo (D4, CONV-VER-2) — requise avant tout patch dépendant version.
- INV-Q3 (allocation auto : remplir un carnet entamé avant d'en ouvrir un nouveau) :
  confirmer ou passer en désignation manuelle exclusive.
- D5/D6 sont des références historiques absentes ou optionnelles dans doc_refonte ; ne pas
  les traiter comme sources obligatoires. Si elles sont réintroduites, elles restent
  subordonnées à D1/D3.
```

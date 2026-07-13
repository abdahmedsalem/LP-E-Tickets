# Concurrence FuelToken — index

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : actif — documentation technique évolutive
autorite      : guide de décision, cartographie, preuves et décisions validées
```

## 1. Objet

Ce sous-répertoire regroupe la documentation relative à :

- la concurrence entre API, portail, back-office et crons ;
- les ressources et invariants partagés ;
- les verrous PostgreSQL/Odoo ;
- les retries serveur et client ;
- l'idempotence ;
- les appels externes ;
- les preuves dynamiques et les décisions prises après test.

Il ne remplace pas les doctrines métier et sécurité de `doc_refonte/`.
Toute décision technique doit rester compatible avec D1 et D2.

## 2. Principe de lecture

Lire dans cet ordre :

```text
1. references/ETAT_ART_MOBILE_RETRY_IDEMPOTENCE_CONCURRENCE.md
2. GUIDE_EVALUATION_CONCURRENCE_FUELTOKEN.md
3. cartographie/RESSOURCES_PARTAGEES.md
4. cartographie/FLUX_WRITERS.md
5. cartographie/MATRICE_FLUX_RESSOURCES.md
6. cartographie/ORDRES_DE_VERROUS.md
7. exemples/ pour reproduire les diagnostics validés
8. decisions/ et preuves/ selon le groupe étudié
```

## 3. Statuts utilisés

| Statut | Sens |
|---|---|
| `FAIT` | Confirmé par une source primaire ou le code de la baseline |
| `INVARIANT` | Propriété qui doit rester vraie |
| `GUIDELINE` | Orientation recommandée, à contextualiser |
| `OPTION` | Solution candidate, non autorisée par défaut |
| `EXPERIENCE` | Test à réaliser ou déjà exécuté |
| `DECISION` | Choix FuelToken validé après preuve |
| `REJET` | Solution écartée dans le périmètre indiqué |
| `OUVERT` | Point non encore tranché |

## 4. Documents

### Référence externe

```text
references/ETAT_ART_MOBILE_RETRY_IDEMPOTENCE_CONCURRENCE.md
```

Synthèse non normative des pratiques Android, PostgreSQL, Odoo, AWS,
Stripe, Adyen et IETF.

### Guide ACPEC

```text
GUIDE_EVALUATION_CONCURRENCE_FUELTOKEN.md
```

Méthode obligatoire pour analyser une ressource ou une action avant patch.

### Cartographie

```text
cartographie/RESSOURCES_PARTAGEES.md
cartographie/FLUX_WRITERS.md
cartographie/MATRICE_FLUX_RESSOURCES.md
cartographie/ORDRES_DE_VERROUS.md
```

La cartographie décrit l'état constaté. Elle ne vaut pas décision d'implémentation.

### Décisions par groupe de ressources

```text
decisions/FACE_LINE_QR.md
decisions/WALLETS_TRANSFERTS.md
decisions/ACHATS.md
decisions/USER_DEVICE_SESSION.md
decisions/OTP_SMS.md
decisions/CRONS_MAINTENANCE.md
```

Une décision ne devient normative qu'après passage explicite au statut `DECISION`.

### Preuves

```text
preuves/PHASE_1A.md
preuves/PHASE_1B_HTTP.md
preuves/PHASE_1B_A2_RETRY_APRES_40001.md
```

Les archives brutes restent externes au dépôt ; les fichiers de preuve conservent
le scénario, la baseline, le résultat et le nom de l'archive.

### Exemples reproductibles

```text
exemples/README.md
exemples/phase1a/Invoke-Phase1AConcurrencyDiagnostic.ps1
exemples/phase1a/phase1a_concurrency_diag.py
exemples/phase1b/Invoke-Phase1BHttpConcurrencyAndIdempotency.ps1
exemples/phase1b/Invoke-Phase1BRetryAfter40001.ps1
```

Ces exemples opèrent uniquement sur une base temporaire clonée. Ils ne sont pas
des tests CI et ne valent pas décision technique.

## 5. Règle de modification

Toute évolution doit préciser :

- baseline ;
- ressource et flux concernés ;
- statut de l'affirmation ;
- preuve ou source ;
- impact API, BO, cron et mobile ;
- tests associés ;
- décision validée ou point restant ouvert.

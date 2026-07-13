# Preuve — Phase 1B-A HTTP concurrence et idempotence

```text
date          : 2026-07-12
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
archive       : phase1b_http_20260712_222904.tar.gz
statut        : PROUVÉ sur base clonée et routes HTTP réelles
```

## Résultats

Trois collisions contrôlées :

```text
deux QR distincts
même face_line
deux stations
```

Chaque paire a produit :

```text
une requête succès
une requête SerializationFailure 40001
```

Réponse publique de l'échec :

```text
SERVER_ERROR
```

L'exception est avalée par le contrôleur ; le retry Odoo n'est pas déclenché.

## Intégrité

Pour chaque paire :

- une seule transaction économique committée avant rejeu ;
- un QR consommé ;
- un QR actif ;
- compteurs conservés ;
- aucun double effet.

## Idempotence après commit

Deux appels avec la même clé et le même payload ont retourné la même transaction.

Même clé avec payload différent :

- refus public ;
- audit interne de mismatch.

## Limites

Le temps d'attente observé incluait un verrou artificiellement retenu.
Il ne constitue pas une mesure de latence production.
## Exemple reproductible

```text
../exemples/phase1b/Invoke-Phase1BHttpConcurrencyAndIdempotency.ps1
```

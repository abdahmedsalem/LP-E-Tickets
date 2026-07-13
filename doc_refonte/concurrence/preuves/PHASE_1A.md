# Preuve — Phase 1A concurrence backend

```text
date          : 2026-07-12
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
archive       : phase1a_runtime_20260712_215135.tar.gz
statut        : PROUVÉ sur base clonée
```

## Scénarios

### Deux QR distincts, même face_line

Résultat :

```text
première transaction → commit
seconde transaction → SerializationFailure 40001
retry transaction fraîche → succès
```

État final :

- conservation des compteurs ;
- aucun compteur négatif ;
- deux QR consommés après retry ;
- aucune corruption silencieuse démontrée.

### Cycle de verrous contrôlé

```text
face_line → QR
QR → face_line
```

Résultat :

```text
DeadlockDetected 40P01
```

### Contention cron

- première phase : erreur propagée sous `lock_timeout` forcé ;
- boucle QR : erreur avalée et cron retournant normalement.

## Limites

- certaines attentes ont été artificiellement forcées ;
- le scénario complet cron réel × API réelle restait à exécuter ;
- aucun patch runtime n'a été appliqué.
## Exemple reproductible

```text
../exemples/phase1a/Invoke-Phase1AConcurrencyDiagnostic.ps1
../exemples/phase1a/phase1a_concurrency_diag.py
```

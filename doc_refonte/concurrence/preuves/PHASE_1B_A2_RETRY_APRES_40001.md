# Preuve — Phase 1B-A2 rejeu après 40001

```text
date          : 2026-07-12
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
archive       : phase1b_retry_after_40001_20260712_224703.tar.gz
statut        : PROUVÉ sur base clonée
```

## Séquence

Collision initiale :

```text
requête A → succès
requête B → 40001 transformé en SERVER_ERROR
```

Contrôle avant rejeu :

```text
clé A → 1 transaction
clé B → 0 transaction
```

Rejeu de B :

```text
même clé
même payload
même fingerprint
→ succès
```

Rejeu suivant :

```text
→ même transaction
```

## Conclusion

Le cycle suivant est compatible avec le contrat backend de la consommation :

```text
40001
→ rollback complet
→ clé non consommée
→ rejeu identique
→ commit unique
→ rejeu idempotent
```

Cette preuve rend le retry transactionnel envisageable.
Elle ne choisit pas le mécanisme ni le nombre de tentatives.
## Exemple reproductible

```text
../exemples/phase1b/Invoke-Phase1BRetryAfter40001.ps1
```

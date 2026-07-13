# Exemples reproductibles de diagnostics de concurrence

```text
nature        : exemples opératoires, non tests CI
environnement : PowerShell + Docker/Odoo/PostgreSQL ACPEC
base source   : lecture/dump uniquement
base test     : clone temporaire horodaté
```

## 1. Finalité

Ces scripts conservent les scénarios représentatifs déjà exécutés pour établir
les preuves Phase 1A, Phase 1B-A et Phase 1B-A2.

Ils servent à :

- reproduire un constat après changement de baseline ;
- comparer une stratégie candidate avant/après patch ;
- conserver la méthode exacte de collecte des preuves ;
- éviter de réinventer un diagnostic à chaque ressource.

Ils ne constituent pas une suite de tests automatique et ne doivent pas être
lancés sur une base de production.

## 2. Environnement par défaut

Les valeurs par défaut correspondent à l'environnement ACPEC utilisé lors des
diagnostics :

```text
Docker directory : D:\docker_for_odoo
Repository       : D:\dev\github\fuelToken
Output           : D:\tmp\fueltoken
Source database  : fueltoken6
PostgreSQL       : postgres16 / postgres16_svc
Odoo             : odoo19 / odoo19_svc
HTTP             : localhost:8019
```

Dans l'environnement courant, le paramètre normalement variable est :

```text
-SourceDatabase
```

Les autres paramètres restent surchargeables en cas de changement futur.

## 3. Mot de passe PostgreSQL

Aucun mot de passe réel n'est committé.

Trois modes sont supportés :

### Invite interactive

Ne rien définir : le script demandera le mot de passe sans l'afficher.

### Variable de session PowerShell

```powershell
$env:FUELTOKEN_DIAG_PG_PASSWORD = "<mot-de-passe-local>"
```

### Paramètre explicite

```powershell
-PgDbPassword "<mot-de-passe-local>"
```

Le paramètre explicite peut apparaître dans l'historique du terminal ; l'invite
interactive ou la variable de session est préférable.

## 4. Garde-fous communs

Les scripts :

- n'exécutent aucune commande Git ;
- n'appliquent aucun patch ;
- ne modifient aucun schéma ;
- créent une base temporaire horodatée ;
- exécutent les fixtures et requêtes sur cette base temporaire ;
- vérifient l'empreinte de la base source avant/après ;
- nettoient la base temporaire sauf `-KeepDiagnosticDatabase` ;
- n'utilisent pas `exit` et ne ferment pas le terminal ;
- produisent un dossier de preuves et une archive.

Avant lancement, vérifier que la base indiquée par `-SourceDatabase` est bien la
base de développement à cloner.

## 5. Phase 1A — transactions backend

Fichiers :

```text
phase1a/Invoke-Phase1AConcurrencyDiagnostic.ps1
phase1a/phase1a_concurrency_diag.py
```

Scénarios :

- deux QR distincts partageant une même `face_line` ;
- conflit de sérialisation et retry dans une transaction fraîche ;
- cycle `face_line → QR` contre `QR → face_line` ;
- contention sur les deux phases du cron d'expiration.

Exécution depuis PowerShell :

```powershell
cd D:\dev\github\fuelToken

& .\doc_refonte\concurrence\exemples\phase1a\Invoke-Phase1AConcurrencyDiagnostic.ps1 `
  -SourceDatabase "fueltoken6"
```

## 6. Phase 1B-A — HTTP réel et idempotence

Fichier :

```text
phase1b/Invoke-Phase1BHttpConcurrencyAndIdempotency.ps1
```

Scénarios :

- trois collisions HTTP réelles sur `/station/qr/use` ;
- deux QR distincts partageant une même `face_line` ;
- même clé et même payload après commit ;
- même clé avec payload différent ;
- preuves DB, audits et error markers ;
- `dbfilter` strict sur la base temporaire.

Exécution :

```powershell
cd D:\dev\github\fuelToken

& .\doc_refonte\concurrence\exemples\phase1b\Invoke-Phase1BHttpConcurrencyAndIdempotency.ps1 `
  -SourceDatabase "fueltoken6"
```

Ce script est plus lourd que Phase 1A. Il lance un conteneur HTTP Odoo temporaire
et produit plusieurs collisions.

## 7. Phase 1B-A2 — rejeu après `40001`

Fichier :

```text
phase1b/Invoke-Phase1BRetryAfter40001.ps1
```

Scénarios :

- une collision HTTP contrôlée ;
- vérification qu'aucune transaction métier n'a été committée pour la clé échouée ;
- rejeu avec la même clé et le même payload ;
- nouveau rejeu idempotent après succès.

Exécution :

```powershell
cd D:\dev\github\fuelToken

& .\doc_refonte\concurrence\exemples\phase1b\Invoke-Phase1BRetryAfter40001.ps1 `
  -SourceDatabase "fueltoken6"
```

## 8. Changement du nom de base

Exemple :

```powershell
& .\doc_refonte\concurrence\exemples\phase1b\Invoke-Phase1BRetryAfter40001.ps1 `
  -SourceDatabase "fueltoken_test"
```

Ne jamais passer le nom de la base temporaire : elle est générée automatiquement.

## 9. Résultats

Les résultats sont écrits sous :

```text
D:\tmp\fueltoken\phase1a_runtime_<timestamp>
D:\tmp\fueltoken\phase1b_http_<timestamp>
D:\tmp\fueltoken\phase1b_retry_after_40001_<timestamp>
```

Chaque script produit notamment :

- un rapport runtime ;
- un résumé ;
- l'état initial/final Docker et PostgreSQL ;
- les réponses ou résultats du scénario ;
- une archive `.tar.gz`, avec fallback `.zip`.

## 10. Usage avant décision

Après exécution :

1. vérifier `main_code`, `cleanup_code` et `archive_code` ;
2. vérifier l'empreinte source inchangée ;
3. lire le résumé et les résultats détaillés ;
4. comparer l'invariant final ;
5. enregistrer la preuve dans `preuves/` ;
6. ne prendre une décision qu'après comparaison des stratégies candidates.

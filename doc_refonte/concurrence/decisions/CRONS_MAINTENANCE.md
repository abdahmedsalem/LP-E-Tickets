# Décision de groupe — crons et maintenance

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : PARTIELLEMENT PROUVÉ
```

## 1. Expiration

Faits :

- phase `face_line`, puis phase QR ;
- conflit de la première phase pouvant faire échouer le cron ;
- boucle QR pouvant avaler une contention et continuer ;
- verrous conservés jusqu'à la fin de la transaction extérieure ;
- cycle possible avec la consommation.

Options :

- batch ;
- ordre aligné avec les APIs ;
- savepoint par unité ;
- `SKIP LOCKED` ;
- reprise au passage suivant ;
- séparation de phases.

Aucune option n'est autorisée seule sans test du retraitement.

## 2. `SKIP LOCKED`

Conditions :

- travail durable et revisitable ;
- passage suivant garanti ;
- retard sans faille métier ;
- métriques de backlog ;
- détection de famine ;
- passe non déclarée exhaustive.

## 3. Purge markers et OTP GC

Ces traitements sont revisités et de priorité inférieure aux mutations économiques.

Orientations :

- batch court ;
- progression observable ;
- pas de gros verrou global ;
- aucune erreur utilisateur dépendante du succès immédiat de la purge.

## 4. Mesures

```text
eligible
processed
skipped_locked
failed
oldest_backlog_age
consecutive_skip_count
last_success
```

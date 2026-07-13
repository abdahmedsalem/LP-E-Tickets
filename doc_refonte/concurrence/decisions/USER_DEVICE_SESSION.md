# Décision de groupe — user, device et session

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : PARTIELLEMENT VALIDÉ
```

## 1. PIN / action_code

### Décision existante

```text
verrou sur res.users
lock_timeout borné
contention → réponse explicite
aucun compteur d'échec ajouté
pas de retry serveur automatique
```

Le but est de sérialiser les actions sensibles d'un même utilisateur.

## 2. `last_seen_at`

### Décision existante

```text
touch throttlé
savepoint
conflit → abandon best-effort
requête principale continue
```

Le savepoint est adapté car cette écriture n'est pas l'invariant principal.

## 3. Refresh de session

Ressources :

```text
session
famille de refresh tokens
device
user
```

Points à confirmer :

- exceptions réellement re-levées ;
- comportement du retry Odoo ;
- concurrence refresh × refresh ;
- refresh × logout ;
- refresh × block/replace device ;
- réponse perdue après rotation ;
- fenêtre de grâce et replay.

Le modèle économique de retry ne doit pas être copié automatiquement sur refresh.

## 4. Device trust et blocage

Tests croisés :

```text
approve API × approve BO
approve × block
block × refresh
replace × session create
```

L'ordre global user/device/session reste à décider après audit complet.

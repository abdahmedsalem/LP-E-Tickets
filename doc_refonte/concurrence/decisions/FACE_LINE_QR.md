# Décision de groupe — face_line, QR et QR lines

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : EN ÉTUDE — faits prouvés, solution non tranchée
```

## 1. Invariant

```text
qty_initial =
  qty_available
+ qty_qr_active
+ qty_qr_blocked
+ qty_consumed
+ qty_expired
+ qty_transferred_out
```

Plusieurs QR peuvent partager une même `face_line`.

## 2. Faits prouvés

- deux QR distincts sur une même `face_line` sont un cas métier réel ;
- deux consommations HTTP concurrentes produisent un `40001`
  dans le runtime Odoo 19 testé ;
- la tentative échouée rollbacke ;
- aucune transaction n'existe pour sa clé avant rejeu ;
- le rejeu avec la même clé et le même payload réussit ;
- le rejeu suivant retrouve la même transaction ;
- aucun lost update silencieux n'a été démontré dans ce scénario ;
- le cycle `face_line → QR` contre `QR → face_line` peut deadlocker.

## 3. Comportement actuel

`/station/qr/use` capture l'exception et la transforme en `SERVER_ERROR`.

Le retry transactionnel Odoo n'est donc pas déclenché sur ce chemin.

Flutter conserve la clé dans la même instance d'intention, mais recrée
actuellement une nouvelle clé lors d'une relance utilisateur depuis l'écran.

## 4. Options à comparer

### Option A — ordre et verrous explicites

- verrouiller la ressource canonique ;
- aligner consommation, expiration, retirer, séparer et BO ;
- relecture après verrou.

Risque : ajouter un verrou isolé sans alignement peut augmenter les deadlocks.

### Option B — retry transactionnel résiduel

- laisser une `SerializationFailure` éligible atteindre la frontière Odoo ;
- budget de tentatives mesuré ;
- métriques et kill-switch.

Risque : politique native Odoo plus large que `40001` si mal intégrée.

### Option C — contrat public et redo client

- distinguer conflit temporaire d'une action réellement en cours ;
- conserver la même intention après issue transitoire ou inconnue.

Cette option complète A/B ; elle ne les remplace pas.

## 5. Décisions déjà prises

```text
REJET : savepoint + retry dans la même transaction pour 40001.
REJET : ajouter uniquement un verrou face_line sans analyse du cron.
GUIDELINE : le retry est résiduel, pas le contrôle primaire.
```

## 6. Expériences restantes

- consommation réelle × cron complet ;
- consommation × blocage/déblocage BO ;
- retirer × consommation ;
- séparer × consommation ;
- émission × consommation/transfert ;
- mesure de latence sans verrou artificiel ;
- test du contrat Flutter avec intention persistée.

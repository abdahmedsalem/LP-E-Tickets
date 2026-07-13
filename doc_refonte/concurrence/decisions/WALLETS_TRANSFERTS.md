# Décision de groupe — wallets et transferts

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : OUVERT — cartographie et tests requis
```

## 1. Flux

- transfert de carnets ;
- transfert de tickets ;
- distribution portail société ;
- éventuels transferts BO ;
- émission QR consommant les mêmes quantités.

## 2. Ressources

```text
wallet source
wallet destination
face_line source
face_line destination éventuelle
transfer
transactions
user/PIN/session
```

## 3. Risques à tester

```text
A→B contre B→A
deux transferts depuis le même wallet
transfert contre émission QR
transfert contre expiration
API contre BO
portail contre mobile
```

## 4. Orientations

- trier les wallets et lignes lorsqu'ils sont verrouillés ;
- ne pas se contenter de l'ordre source puis destination ;
- protéger la disponibilité sous verrou ;
- conserver une transaction économique unique par intention ;
- vérifier les deux côtés source/destination après rollback.

## 5. Retry

Le retry `40001` reste une `OPTION`.

Il ne devient candidat qu'après :

- ordre multi-wallet validé ;
- rollback complet prouvé ;
- idempotence après commit prouvée ;
- absence d'effet externe ;
- test A→B × B→A ;
- test transfer × issue.

# Ordres de verrous — état constaté et méthode de décision

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : ordre global non encore tranché
```

## 1. Règle

L'ordre doit être cohérent entre tous les writers touchant les mêmes ressources :

```text
API
portail
BO
cron
```

Un ordre local correct dans une opération peut rester incompatible avec un autre flux.

## 2. Ordres observés

### Consommation station

```text
QR
→ QR lines / logique
→ écritures face_line
→ transaction
```

### Cron expiration

```text
phase 1 : face_line
phase 2 : QR
```

Un cycle mécanique `face_line → QR` contre `QR → face_line`
a produit un deadlock dans le diagnostic Phase 1A.

### Émission QR

```text
wallet / allocations
→ face_line
→ création QR et QR lines
```

Ordre exact multi-`face_line` à confirmer.

### Retirer / séparer

```text
QR
→ QR lines
→ face_line selon les helpers et mouvements
```

### Transferts

```text
wallets
→ face_line source/destination
→ transfer / transactions
```

Ordre entre wallets opposés et ordre des lignes à confirmer.

### User / device / session

Plusieurs flux touchent :

```text
user
device
sessions
```

L'ordre transversal entre refresh, block, replace et approve doit être cartographié.

## 3. Règles de construction

- ids d'une même classe triés ;
- ordre SQL visible lorsque l'ordre d'acquisition importe ;
- relecture après acquisition ;
- aucun ancien recordset après rollback complet ;
- même ordre dans API, BO et cron ;
- tests croisés, pas seulement même opération × même opération.

## 4. Décision ouverte

Aucun ordre global tel que :

```text
wallet → QR → face_line
```

ou :

```text
wallet → face_line → QR
```

n'est autorisé par ce document.

Il doit être choisi après la matrice complète du groupe économique
et des scénarios croisés.

## 5. Critères de validation

L'ordre candidat doit être testé sur :

```text
consume × cron
consume × block QR
issue × transfer
retirer × consume
separer × consume
transfer A→B × transfer B→A
purchase approve API × BO
refresh × device block
```

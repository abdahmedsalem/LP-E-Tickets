# Décision de groupe — achats

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : OUVERT — tests croisés requis
```

## 1. Flux

- soumission client ;
- approbation manager API ;
- approbation BO ;
- rejet API/BO ;
- création de carnets et `face_line` ;
- transaction publique du cycle.

## 2. Invariants

- une demande ne reçoit qu'une décision terminale ;
- approbation et rejet ne gagnent pas simultanément ;
- les carnets ne sont créés qu'une fois ;
- la transaction publique reste cohérente avec la doctrine métier ;
- une relance idempotente retrouve le même résultat.

## 3. Concurrences à tester

```text
approve API × approve BO
approve × reject
double approve manager
soumission rejouée après réponse perdue
approbation pendant modification autorisée éventuelle
```

## 4. Points à vérifier

- clé et fingerprint par route ;
- verrou ou transition atomique sur l'achat ;
- créations liées rollbackées ;
- séquences ;
- notifications/chatter ;
- effet externe éventuel ;
- résultat stocké pour rejeu.

## 5. Retry

Aucune allowlist avant validation des points précédents.

Le retry ne doit pas compenser une transition d'état non atomique.

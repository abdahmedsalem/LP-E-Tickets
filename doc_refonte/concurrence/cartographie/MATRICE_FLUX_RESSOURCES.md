# Matrice flux × ressources

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : matrice initiale à compléter pendant les audits
```

Légende :

```text
R   lecture
W   écriture
C   création
L   verrou explicite observé
E   effet externe
?   chaîne à confirmer
```

| Flux | Purchase | Wallet | Face line | QR | QR line | Transaction | User | Device | Session | OTP | Externe |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Purchase create | C/W | R | — | — | — | C | R | — | R | — | — |
| Purchase approve | L/W | R | C | — | — | W/C | R | — | R | — | notification ? |
| Purchase reject | L/W | — | — | — | — | ? | R | — | R | — | notification ? |
| QR issue | — | R/L | W | C | C | C | PIN | — | R | — | — |
| QR check | — | — | W ? | R/L/W | R | — | R | — | R | — | — |
| QR use | — | — | W | L/W | R/W | C | PIN | — | R | — | — |
| QR retirer | — | R | W | L/W/C | L/W/C | C | PIN | — | R | — | — |
| QR separer | — | R | W | L/W/C | L/W/C | C | PIN | — | R | — | — |
| Ticket transfer | — | L/W | W/C | — | — | C | PIN | — | R | — | — |
| Carnet transfer | — | L/W | W/C | — | — | C | PIN | — | R | — | — |
| Portal distribution | — | L/W | W/C | — | — | C | R | — | R | — | — |
| Cron expiration | — | — | L/W | L/W | R/W | C ? | — | — | — | — | — |
| PIN verify | — | — | — | — | — | — | L/W | — | R | — | — |
| Request OTP | — | — | — | — | — | — | R | — | — | C/W | E SMS |
| Verify OTP | — | — | — | — | — | — | W ? | C/W ? | C/W ? | L/W | — |
| Login | — | — | — | — | — | — | R | C/W | C | — | — |
| Refresh | — | — | — | — | — | — | R | R/W | L/W | — | — |
| Logout | — | — | — | — | — | — | R | R | W | — | — |
| Device approve/block | — | — | — | — | — | — | R/L | L/W | L/W | — | — |
| Last seen touch | — | — | — | — | — | — | — | — | W best-effort | — | — |
| Marker purge | — | — | — | — | — | — | — | — | — | — | marker |
| OTP bucket GC | — | — | — | — | — | — | — | — | — | W | — |

## Lecture de la matrice

Cette table ne définit pas encore un ordre global.

Elle sert à identifier :

- les ressources chaudes ;
- les flux multi-ressources ;
- les conflits croisés ;
- les effets externes ;
- les colonnes nécessitant un audit approfondi.

Les symboles `?` doivent être résolus avant une décision concernant le flux.

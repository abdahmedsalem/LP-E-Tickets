# ADR-003 - Refresh token rotatif avec fenêtre de grâce

## Statut

Accepté V1.

## Décision

Refresh token rotatif avec fenêtre de grâce courte, fixe, non extensible.

## Raison

La rotation stricte immédiate casse si la réponse `/refresh` est perdue par le réseau.

## Conséquence

Pendant la fenêtre, un ancien token peut être accepté comme retry réseau probable. Hors fenêtre, sa réutilisation révoque la session.

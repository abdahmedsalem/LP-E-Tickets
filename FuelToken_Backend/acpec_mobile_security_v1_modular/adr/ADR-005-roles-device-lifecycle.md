# ADR-005 - Rôle attribué != device trusted

## Statut

Accepté V1.

## Décision

Un rôle sensible attribué par back-office ne rend pas le device trusted.

## Raison

Sinon un SIM swap permettrait d'enrôler un nouveau device et d'exploiter immédiatement le rôle station/manager déjà attribué.

## Conséquence

User state, rôle mobile et device trust sont trois axes séparés.

## Décisions complémentaires clôturées

```text
OPEN-CLIENT-001 : volume cible clients mobiles <= 5000 ; res.users par client accepté en V1.
OPEN-MANAGER-001 : manager_field_validation_enabled=False par défaut.
```


## Clarification cohérence

Tous les rôles mobiles sont attribués par back-office. Un manager terrain, même trusted, ne peut pas accorder `mobile_station_user` ni `mobile_manager_user`. Le trust client par cooldown système est autorisé uniquement pour `mobile_base_user` et ne lève pas les restrictions haute valeur.

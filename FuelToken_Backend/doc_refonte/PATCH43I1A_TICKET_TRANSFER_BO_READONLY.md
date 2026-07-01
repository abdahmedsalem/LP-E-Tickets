# Patch43I1A — Transfert de tickets BO lecture seule

Patch43I1A aligne le modèle `acpec.fuel.ticket.transfer` avec la doctrine mobile.

## Doctrine

Les transferts de tickets sont des données issues d'une action du user mobile app.
Ils ne doivent pas être créés, modifiés ou supprimés comme opérations back-office.

Le back-office peut lire les transferts pour audit/support, mais ne les initie pas en V1.

## Règles

- `group_fuel_user` : lecture de ses transferts source/destination uniquement ;
- `group_fuel_manager` : lecture audit société uniquement ;
- `group_fuel_admin` : lecture audit société uniquement ;
- création/modification/suppression réservées au contexte interne backend ;
- futur endpoint mobile : user source authentifié, device trusted, action_code/PIN, idempotency_key et validations métier.

## Contextes internes réservés

```text
allow_fuel_ticket_transfer_create
allow_fuel_ticket_transfer_update
allow_fuel_ticket_transfer_unlink
```

Ces contextes sont réservés aux primitives backend contrôlées, tests, maintenance/migration explicite et futur endpoint mobile sécurisé.

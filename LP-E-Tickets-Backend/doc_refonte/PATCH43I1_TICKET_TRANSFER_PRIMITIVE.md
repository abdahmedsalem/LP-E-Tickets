# Patch43I1 — Primitive interne transfert de tickets

Patch43I1 introduit le flux backend séparé `acpec.fuel.ticket.transfer` / `acpec.fuel.ticket.transfer.line` pour transférer une quantité de tickets entiers disponibles.

## Doctrine

Le transfert de tickets ne réutilise pas `acpec.fuel.carnet.transfer`.

Il applique la mécanique suivante :

- la ligne source reste dans le wallet source ;
- `qty_available` diminue ;
- `qty_transferred_out` augmente ;
- `qty_initial` source reste inchangé ;
- une nouvelle `acpec.fuel.face.line` fragment est créée dans le wallet destination ;
- le fragment destination reçoit sa propre identité `carnet_no` / `carnet_short_code` ;
- le fragment conserve `purchase_id`, `purchase_line_id`, `origin_face_line_id` et `origin_ticket_transfer_line_id` ;
- deux transactions append-only `transfert_ticket` sont créées, une sortante source et une entrante destination.

## Hors périmètre

Patch43I1 ne crée pas encore endpoint mobile public, wizard BO ni UI Flutter.

## Garde-fous

- source != destination ;
- même société obligatoire ;
- motif obligatoire ;
- quantité strictement positive ;
- quantité transférée <= `qty_available` ;
- aucun QR ni bucket non disponible n'est transféré ;
- un transfert confirmé est immuable ;
- `action_confirm()` est idempotent si le transfert est déjà confirmé.

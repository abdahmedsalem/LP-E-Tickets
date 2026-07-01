# Patch43I3 — Flutter transfert de tickets

## Objet

Ajouter le flux mobile Flutter de transfert de tickets après la clôture backend Patch43I2/J0.

## UX accueil

Les actions rapides client passent sur deux lignes de deux cartes, avec verbes à l’infinitif :

- Acheter des carnets
- Créer un bon de retrait
- Transférer des carnets
- Transférer des tickets

## Doctrine

- Transfert de carnets : carnet intact, flux existant.
- Transfert de tickets : quantité de tickets disponibles d’une ou plusieurs lignes `face_line`.
- Le code QR / code manuel n’est pas transféré.
- Le transfert de tickets appelle `/api/acpec/fueltoken/v1/mobile/tickets/transfer`.
- Payload : `recipient_phone`, `note`, `lines[{face_line_id, qty_tickets}]`, `action_code`, `idempotency_key`.
- La note/motif est obligatoire côté UI car elle est obligatoire côté backend. Elle est saisie sur l’écran de confirmation, juste avant le PIN/action_code, pour garder le premier écran centré sur le destinataire et les quantités.

## UX transfert de tickets

- Le premier écran ne contient plus le footer de navigation client.
- Le bouton principal de transfert reste accessible en bas d’écran pendant le choix des quantités.
- Le motif est saisi sur le second écran de confirmation, avant la demande de PIN.

## Sécurité

Le PIN/action_code passe par le dialogue existant d’action sensible. L’idempotency key est générée par `SensitiveActionIntent` avec l’opération `ticket-transfer`.

## Observabilité

Avec Patch43J0, les essais du flux doivent produire côté Odoo les marqueurs :

- `[[ACPEC_FUELTOKEN_API_IN]] endpoint=mobile.tickets.transfer operation=ticket_transfer`
- `[[ACPEC_FUELTOKEN_API_OUT]] endpoint=mobile.tickets.transfer operation=ticket_transfer`
- `[[ACPEC_FUELTOKEN_API_REFUSED]] endpoint=mobile.tickets.transfer operation=ticket_transfer`

## Limites volontaires

- Pas de modification BO.
- Pas de fusion entre transfert de carnets et transfert de tickets.
- Pas de révélation ni transfert de secret QR.

## Patch43I3B — alignement UX transfert

- Écran `Transfert de carnets` : titre explicite, footer sticky `TOTAL TRANSFERT` + bouton `Continuer`, suppression du footer navigation interne.
- Écran `Transfert de tickets` : même footer sticky que les écrans `Commander` et `Générer QR Code`.
- Le motif reste saisi sur l'écran de confirmation avant le PIN/action_code.

## Ajustement motif facultatif

- Le motif est saisi sur l'écran de confirmation pour `Transfert de carnets` et `Transfert de tickets`.
- Le motif est facultatif côté Flutter.
- Si l'utilisateur laisse le champ vide, le frontend envoie `Motif non renseigné`.
- Aucun patch backend n'est requis pour terminer I3 côté Flutter.


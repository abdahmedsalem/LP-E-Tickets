# Patch43I2 — Endpoint mobile transfert de tickets

## Objet

Patch43I2 expose le flux de transfert de tickets côté mobile, sans création BO.

Le transfert de tickets est initié par le client mobile source et confirmé par le backend après validation sécurité.

## Endpoint

```text
/api/acpec/fueltoken/v1/mobile/tickets/transfer
```

Payload attendu :

```text
recipient_phone
lines = [{face_line_id, qty_tickets}]
note
idempotency_key
action_code
```

## Règles

```text
- device source trusted ;
- user source avec rôle client ;
- action_code / PIN obligatoire ;
- idempotency_key obligatoire ;
- destination identifiée par téléphone mobile canonique ;
- destination active, même société, rôle client ;
- source != destination ;
- qty_tickets > 0 ;
- qty_tickets <= qty_available via primitive I1 ;
- note obligatoire ;
- création via contexte interne allow_fuel_ticket_transfer_create ;
- BO reste lecture/audit uniquement.
```

## Contrat terminologique

On dit transfert de tickets. Le ticket transféré reste un ticket entier.

Le fragment est la ligne destination créée par le backend, pas un ticket coupé.

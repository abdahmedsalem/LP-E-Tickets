# ADR-004 - Portée de la clé d'idempotence

## Statut

Accepté V1.

## Décision

La clé d'unicité idempotence est :

```text
operation_type + operator_user_id + idempotency_key
```

avec `company_id` si nécessaire.

`mobile_session_id` et `device_uid` sont audit, pas clé d'unicité.

## Raison

Un retry après reconnexion ou nouvelle session doit rester idempotent.

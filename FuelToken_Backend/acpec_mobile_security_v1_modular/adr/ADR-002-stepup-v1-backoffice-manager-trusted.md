# ADR-002 - Step-up V1 par back-office ou manager trusted

## Statut

Accepté V1.

## Décision

Le step-up V1 se limite à :

```text
- validation back-office ;
- validation manager depuis device déjà trusted, bornée au périmètre agent station, uniquement si `manager_field_validation_enabled=True`.
```

OTP SMS n'est pas utilisé comme step-up contre SIM swap ou nouveau device.

## Raison

Un OTP SMS ne protège pas contre une attaque où l'attaquant contrôle la SIM ou le nouveau device.

## Conséquence

La V1 privilégie un mécanisme moins automatique mais plus contrôlable et auditable.

## Décision de configuration V1

```text
manager_field_validation_enabled = False par défaut.
```

Donc, en V1 standard, le back-office est seul validateur. La validation manager trusted est une option terrain à activer explicitement.


## Clarification cohérence

Le step-up V1 ne bypass jamais ponctuellement `device_trust_state == trusted`. Il produit le trust du device. Par défaut, seule la validation back-office est active. La validation manager est désactivée (`manager_field_validation_enabled=False`) et, si activée, ne peut jamais accorder ni retirer un rôle. Le canal `system_cooldown` est distinct et limité aux clients `mobile_base_user` avec `trust_scope=low_value_only`.

# AGENTS - Règles de contexte pour IA / dev agentic

Avant toute modification de code liée à ACPEC Mobile Security :

1. Charger `00_decisions_invariants.md`.
2. Charger uniquement le ou les modules pertinents.
3. Ne pas utiliser l'ancien monolithe ou l'ancien additif comme source active.
4. Ne jamais inventer une règle absente des modules.
5. En cas de contradiction apparente : `00_decisions_invariants.md` gagne, puis le module spécialisé.
6. En cas de règle non tranchée : créer une question ou une décision `OPEN-*`, ne pas coder par supposition.

Exemples :

```text
Corriger login OTP
-> lire 00 + 02 + 08 + 09.

Corriger refresh token
-> lire 00 + 03 + 09.

Changer rôles station/manager
-> lire 00 + 01 + 04 + 06 + 09.

Consommation QR
-> lire 00 + 04 + 06 + 07 + 09.
```

## Rappels V1 clos

- `manager_field_validation_enabled=False` par défaut : ne pas coder la validation manager comme active par défaut.
- Un manager ne peut jamais accorder ni retirer un rôle mobile, même station.
- `system_cooldown` est autorisé uniquement pour clients `mobile_base_user`, avec `trust_scope=low_value_only`.
- Volume clients mobiles V1 <= 5000 : `res.users` par client accepté ; ne pas utiliser signup portail standard.

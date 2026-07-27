# ADR-001 - Mobile user comme portal-type Odoo

## Statut

Accepté V1.

## Décision

Le mobile user ACPEC est un `res.users` de type portail Odoo (`base.group_portal`) spécialisé mobile, avec `acpec_mobile_only=True` et `acpec_mobile_auth.group_mobile_auth_user`.

## Raison

Odoo classe les utilisateurs externes via le type portail. Un `res.users` sans type Odoo clair crée des risques d'incohérence ACL/record rules.

## Garde-fous

- Aucun credential web exploitable : `password=False` ou équivalent sans mot de passe web utilisable.
- Pas de `base.group_user`.
- Audit ACL/rules `base.group_portal`.
- APIs mobiles vérifient les groupes/champs mobiles, pas seulement `base.group_portal`.

## Clarification post-POC 2026-06-19

Le POC Odoo 19 a montré que `base.group_portal` apporte une surface ACL/rules large. Cette observation ne remet pas en cause la décision portal-type : elle renforce la nécessité de `acpec_mobile_only=True` et du blocage explicite des credentials web.

Le portail est un type technique Odoo, pas une autorisation fonctionnelle mobile.

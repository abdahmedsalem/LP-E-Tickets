# 06 - Intégration Odoo, portal grants et FuelToken station

## Portée

Ce module définit l'intégration ORM Odoo, le risque `base.group_portal`, l'usage de `with_user` / `sudo`, et les règles station FuelToken.

Lire avec `00_decisions_invariants.md`, `01_users_roles_lifecycle.md`, `04_device_trust_stepup.md` et `07_idempotency.md`.

## 6.1 Risque portal grants

Le mobile user doit avoir `base.group_portal` pour être un portal-type Odoo valide.

Mais `base.group_portal` apporte des ACL et record rules de modules Odoo et ACPEC.

Risque :

```text
Dans un appel mobile with_user(mobile_user), les règles portail peuvent élargir ou modifier la portée des données.
```

Règle :

```text
Aucun endpoint mobile ne se contente de base.group_portal.
```

### POC terrain 2026-06-19 - conséquence

Le POC Odoo 19 a confirmé que `base.group_portal` apporte des ACL/rules sur de nombreux modèles standard et FuelToken : ventes, factures, lignes comptables, partenaires, utilisateurs, API keys, passkeys, TOTP, payment tokens, mail/discuss et objets portail société.

Conclusion V1 : on garde `base.group_portal` pour le type Odoo, mais on ne l'utilise jamais comme preuve d'autorisation mobile. Les endpoints mobiles doivent d'abord vérifier `acpec_mobile_only`, la session mobile, le device trust, le rôle mobile, l'affectation métier et l'idempotence.


Chaque endpoint mobile vérifie :

```text
acpec_mobile_enabled ;
acpec_mobile_only ;
group_mobile_auth_user ;
session ;
device_trust_state ;
rôle mobile ;
société ;
station/affectation ;
règles métier ;
idempotence.
```

## 6.2 Objectif with_user

Pour les modèles ACPEC purs, l'objectif est :

```python
record.with_user(mobile_user).action_xxx()
model.with_user(mobile_user).create(vals)
```

Bénéfices :

```text
create_uid réel ;
write_uid réel ;
ACL appliquées ;
record rules appliquées ;
audit Odoo cohérent.
```

Mais `with_user(mobile_user)` doit être validé opération par opération par POC.

## 6.3 Usage contrôlé de sudo

`sudo()` est autorisé pour les opérations techniques :

```text
OTP ;
session ;
token ;
refresh ;
révocation ;
lecture config ;
recherche initiale ;
cron ;
opérations système.
```

Pour métier, `sudo()` est exceptionnel.

Si `sudo()` est nécessaire dans une opération métier :

```text
operator_user_id obligatoire ;
mobile_session_id obligatoire ;
device_uid obligatoire ;
station_id si applicable ;
company_id obligatoire ;
idempotency_key obligatoire.
```

## 6.4 Station FuelToken

```text
acpec.fuel.station
-> station physique ou point de consommation.

res.users mobile
-> agent ou opérateur mobile.

acpec.fuel.station.agent
-> affectation station <-> mobile user.
```

Une opération station vérifie :

```text
station active ;
agent affecté ;
affectation active ;
company_id ;
rôle station ;
user approved ;
device trusted ;
session valide.
```

Transaction station garde :

```text
station_id
operator_user_id
mobile_session_id
device_uid
company_id
idempotency_key
```

## 6.5 POC obligatoire with_user

Cas recommandé : consommation QR station.

À vérifier :

```text
pas d'AccessError inattendu ;
pas de fuite via règles portail ;
create_uid correct ;
operator_user_id correct ;
station_id correct ;
mobile_session_id correct ;
company_id correct.
```

## 6.6 Tests minimum

```text
- mobile user portal-type peut lire uniquement son périmètre attendu ;
- endpoint mobile refuse user portal standard non mobile ;
- endpoint mobile refuse mobile user sans rôle requis ;
- station agent hors station refusé ;
- cross-company refusé ;
- with_user POC passe ou décision sudo audité documentée ;
- sudo métier sans audit échoue en test.
```

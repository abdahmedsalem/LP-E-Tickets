# 01 - Users, rôles et cycle de vie

## Portée

Ce module définit les familles d'utilisateurs, la forme du mobile user, les rôles mobiles, l'attribution des rôles et l'état du compte mobile.

Lire avec `00_decisions_invariants.md`.

## 1.1 Trois familles d'utilisateurs

### Back-office user

Utilisateur interne Odoo.

```text
Groupe obligatoire : base.group_user
Canal : /web Odoo standard
Sécurité : session Odoo, ACL, record rules, menus back-office
```

Il peut avoir des groupes métier back-office, par exemple `acpec_fueltoken_base.group_fuel_admin`.

Il ne passe pas par `acpec_mobile_auth`.

### Portal user standard

Utilisateur portail Odoo classique.

```text
Groupe : base.group_portal
Canal : portail Odoo standard
Login : credential portail si actif
```

Il n'est pas automatiquement mobile user.

### Mobile user ACPEC

Mobile user = `res.users` portal-type spécialisé mobile.

```text
base.group_portal
acpec_mobile_auth.group_mobile_auth_user
acpec_mobile_enabled = True
acpec_mobile_only = True
acpec_mobile_state = pending | approved | blocked
acpec_mobile_phone = numéro utilisé pour OTP
```

Interdit :

```text
base.group_user
base.group_public
acpec_fueltoken_base.group_fuel_admin
credential web exploitable, notamment mot de passe web
```


### Clarification importante

`base.group_portal` est un **type technique Odoo obligatoire** pour éviter un `res.users` externe sans type clair. Il ne signifie pas que le compte mobile peut utiliser le portail web standard.

Pour un compte `acpec_mobile_only=True`, l'état attendu est :

```text
base.group_portal = présent
acpec_mobile_auth.group_mobile_auth_user = présent
acpec_mobile_only = True
password = False ou aucun mot de passe web utilisable
reset/signup/API key/passkey/TOTP web = bloqués ou inutilisables
```

## 1.2 Hardening mobile_only

Pour `acpec_mobile_only=True` :

```text
- `password=False` au provisioning, ou équivalent Odoo garantissant l'absence de mot de passe web utilisable ;
- pas de reset password portail ;
- pas de signup portail ;
- pas d'invitation portail standard ;
- pas d'API key utilisable/créable par le compte mobile ;
- pas de passkey web utilisable/créable par le compte mobile ;
- pas de TOTP web enrôlable comme mécanisme de connexion portail ;
- pas de login web volontaire.
```

La protection ne doit pas reposer sur une redirection `/web` ou `/my`, mais sur l'absence native de credential web et sur le blocage serveur des surfaces web/portail non mobiles.

## 1.3 Contraintes Odoo sur res.users

Une contrainte modèle doit empêcher les états incohérents.

```python
if user.acpec_mobile_only:
    require(base.group_portal)
    require(acpec_mobile_auth.group_mobile_auth_user)
    forbid(base.group_user)
    forbid(base.group_public)
    forbid(acpec_fueltoken_base.group_fuel_admin)
    require_password_false_or_no_web_password(user)
    require_no_web_credential(user)
    block_reset_signup_api_key_passkey_totp_for_mobile_only(user)
```

## 1.4 Rôles mobiles

Un rôle mobile = un groupe Odoo dédié au mobile.

FuelToken V1 :

```text
mobile_base_user    -> acpec_fueltoken_base.group_fuel_user
mobile_station_user -> acpec_fueltoken_base.group_fuel_station
mobile_manager_user -> acpec_fueltoken_base.group_fuel_manager
```

Règles :

```text
Un manager mobile n'est pas automatiquement station.
Un agent station n'est pas automatiquement manager.
Un utilisateur de base n'est pas automatiquement station.
```

Chaque endpoint vérifie explicitement le rôle requis.

## 1.5 Attribution des rôles

Les rôles mobiles ne sont jamais choisis par l'utilisateur mobile.

L'utilisateur ne peut pas se déclarer lui-même :

```text
agent station ;
manager ;
validateur ;
administrateur.
```

Les rôles sont attribués uniquement par le back-office.

```text
Le manager terrain ne peut jamais accorder ni retirer un rôle mobile.
Il peut seulement, si `manager_field_validation_enabled=True`, valider/truster un device station ou activer un agent station déjà créé dans son périmètre, selon le module 04.
```

## 1.6 Création d'un mobile user

À la création, le mobile user reçoit toujours le socle minimal :

```text
base.group_portal
acpec_mobile_auth.group_mobile_auth_user
acpec_mobile_enabled = True
acpec_mobile_only = True
acpec_mobile_state = pending
```

Rôle par défaut V1 :

```text
Tout nouveau mobile user commence avec mobile_base_user,
sauf si le back-office crée explicitement le compte pour un rôle précis.
```

Le rôle minimal ne donne jamais automatiquement station ou manager.

## 1.7 Rôles sensibles

Rôles sensibles :

```text
mobile_station_user
mobile_manager_user
```

Ils ne sont jamais accordés automatiquement après OTP.

Le back-office peut créer directement un utilisateur avec un rôle sensible, mais :

```text
rôle attribué != device trusted
```

Même si le rôle station est déjà attribué, le nouveau device reste `pending_trust` jusqu'à validation.

## 1.8 Action back-office dédiée

Le back-office dispose d'une action dédiée, pas d'une modification libre des groupes.

Actions autorisées :

```text
ajouter / retirer mobile_station_user ;
ajouter / retirer mobile_manager_user ;
bloquer / réactiver / valider le mobile user ;
révoquer un device ;
marquer un device comme trusted.
```

Garde-fous :

```text
base.group_portal reste obligatoire ;
group_mobile_auth_user reste obligatoire ;
base.group_user interdit ;
base.group_public interdit ;
group_fuel_admin interdit ;
aucun credential web généré.
```

## 1.9 États du mobile user

```text
pending  -> compte créé, pas encore validé pour usage complet.
approved -> compte mobile validé.
blocked  -> compte bloqué, aucune session mobile utilisable.
```

Un user `pending` peut finaliser OTP et PIN selon le workflow, mais ses opérations sensibles restent bloquées.

Un user `blocked` révoque immédiatement toutes ses sessions.

## 1.10 Audit changement de rôle

Champs audit :

```text
changed_by
changed_at
old_roles
new_roles
reason
```

## 1.11 Provisioning client - décision V1

Le signup portail Odoo standard est interdit pour les mobile users.

Décision V1 :

```text
Volume cible clients mobiles <= 5000.
Le modèle res.users par client est accepté en V1.
```

Voies autorisées :

```text
- création back-office ;
- endpoint d'onboarding contrôlé qui applique obligatoirement le socle mobile_only ;
- jamais via signup portail Odoo standard.
```

Si le volume cible dépasse 5000 ou si l'usage devient B2C massif, ouvrir une nouvelle ADR et réévaluer :

```text
res.users par client
vs
identité mobile séparée / modèle acpec.mobile.identity.
```

## 1.12 Tests minimum

```text
- mobile user créé avec socle technique ;
- mobile user sans credential web ;
- mobile user avec base.group_user refusé ;
- mobile user avec base.group_public refusé ;
- mobile user avec group_fuel_admin refusé ;
- rôle station non accordé par OTP ;
- rôle station non accordé par manager terrain ;
- rôle manager accordé uniquement back-office ;
- changement de rôle audité ;
- client mobile créé uniquement par back-office ou endpoint contrôlé ;
- aucun mobile user créé par signup portail standard.
```

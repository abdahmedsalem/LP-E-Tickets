# ACPEC FuelToken Company Accounts

Module Odoo 19 pour gérer les **Comptes Sociétés** FuelToken dans le back-office ACPEC.

Version : `19.0.1.3.0`.

## Doctrine fonctionnelle

Un Compte Société est une entité séparée du flux mobile existant.

- **Mobile users** : flux mobile existant, APIs mobile inchangées.
- **Comptes Sociétés** : flux portail/web séparé.
- **Back-office ACPEC** : création, gestion, validation et audit.

Le module ne modifie pas les APIs mobile, ne crée pas de contrôleur mobile et ne change pas le comportement du signup mobile.

## Modèle métier

Le modèle principal est :

```text
acpec.fuel.distributor
```

Il représente la relation suivante :

```text
Compte Société
= partner société avec accès portail Odoo standard
+ membres partenaires individuels
```

Champs principaux :

- `partner_id` : société partenaire (`res.partner`, `is_company = True`).
- `member_partner_ids` : membres/employés rattachés à la société (`res.partner`, `is_company = False`).
- `state` : brouillon, actif, suspendu, clôturé.
- `code` : code unique par société Odoo.
- `company_id` : société Odoo.
- `wallet_id` : wallet FuelToken technique de la société, calculé si existant.
- `contact_name`, `contact_phone`, `contact_email` : informations de contact back-office.

## Accès portail requis

Le Compte Société doit utiliser l’accès portail Odoo standard.

Le module **ne crée pas** d’utilisateur portail automatiquement. Le flux attendu est :

1. Créer ou sélectionner la société dans **Contacts**.
2. Utiliser l’action standard Odoo **Donner accès au portail** sur ce contact société.
3. Créer le Compte Société FuelToken et sélectionner cette société comme `partner_id`.
4. Ajouter les membres dans `member_partner_ids`.

## Contraintes de création

La création d’un Compte Société est refusée si :

- le partenaire sélectionné n’est pas une société (`is_company = False`) ;
- le partenaire n’a pas d’utilisateur portail Odoo actif ;
- le partenaire est déjà associé à un utilisateur interne Odoo ;
- le partenaire est déjà associé à un utilisateur mobile FuelToken ;
- le partenaire est déjà associé à un utilisateur station ou back-office FuelToken ;
- la société partenaire est aussi listée comme membre ;
- un membre sélectionné est une société au lieu d’un individu.

Groupes incompatibles pour le partenaire société :

- `base.group_user` ;
- `acpec_fueltoken_base.group_fuel_user` ;
- `acpec_fueltoken_base.group_fuel_station` ;
- `acpec_fueltoken_base.group_fuel_manager` ;
- `acpec_fueltoken_base.group_fuel_admin`.

Le seul groupe utilisateur attendu pour le partenaire société est le portail Odoo standard (`base.group_portal`).

## Doctrine membres et mobile actif

Un membre peut être ajouté au roster d’un Compte Société même s’il n’est pas encore prêt côté mobile.

Mais une distribution vers ce membre est refusée tant que le membre n’a pas un utilisateur mobile FuelToken actif et approuvé :

```text
res.users.active = True
res.users.partner_id = membre
res.users.company_ids contient company_id du Compte Société
appartenance au groupe acpec_fueltoken_base.group_fuel_user vérifiée via res_groups_users_rel
res.users.mobile_state = approved
```

La distribution société ne valide jamais automatiquement un compte mobile, ne change jamais `mobile_state` et n’ajoute jamais de groupe mobile.

## Backend distribution

Le module porte maintenant les méthodes backend de distribution société. Le futur espace web `FuelToken_WebClient` ou `acpec_fueltoken_company_portal` devra appeler ces méthodes au lieu de réimplémenter le métier.

Méthodes principales sur `acpec.fuel.distributor` :

```python
action_prepare_member_wallets()
action_distribute_to_member(member_partner, lines, note=False, idempotency_key=False, confirm=True)
action_distribute_bulk(distribution_lines, idempotency_key=False)
```

### Préparation wallets membres

`action_prepare_member_wallets()` crée les wallets techniques des membres qui ont déjà un compte mobile actif et approuvé.

Elle ne valide pas les utilisateurs mobiles. Les membres non prêts sont signalés dans le chatter.

### Distribution vers un membre

`action_distribute_to_member(...)` crée et confirme un `acpec.fuel.carnet.transfer` standard :

```python
transfer = distributor.action_distribute_to_member(
    member_partner,
    [
        {'face_line_id': 10, 'carnet_qty': 2},
    ],
    note='Distribution mensuelle',
    idempotency_key='WEB-123',
)
```

La méthode vérifie :

- le Compte Société est actif ;
- le partenaire société est toujours portal-only ;
- le destinataire est membre du Compte Société ;
- le destinataire est un membre individuel ;
- le destinataire a un compte mobile actif et approuvé ;
- le wallet société existe ou est créé à la demande ;
- le wallet membre existe ou est créé à la demande ;
- les lignes source appartiennent au wallet société ;
- les lignes source sont transférables en carnets intacts ;
- l’idempotence est respectée via `idempotency_key`.

Le moteur de transfert reste celui du core : `acpec.fuel.carnet.transfer.action_confirm()`.

## Garde-fous métier inclus

Le module contient aussi des garde-fous pour éviter que le Compte Société se comporte comme un utilisateur mobile :

- un Compte Société ne peut pas recevoir de transfert entrant manuel ;
- une société active peut distribuer uniquement vers ses membres ;
- une société suspendue, clôturée ou archivée ne peut pas distribuer ;
- une distribution vers un membre non mobile actif/approuvé est refusée ;
- un Compte Société ne peut pas générer de QR ;
- un achat pour une société suspendue/clôturée est refusé au moment de la soumission si le hook `_check_before_submit` est appelé par le module achat.

Ces garde-fous ne modifient pas les APIs mobile.

## Back-office

Le menu est ajouté sous :

```text
FuelToken > Comptes Sociétés > Comptes Sociétés
```

La création est autorisée car il s’agit d’un objet d’onboarding.

La suppression est interdite. Il faut suspendre, clôturer ou archiver pour conserver la traçabilité.

Le bouton **Préparer wallets membres** est disponible sur un Compte Société actif.

## Séparation avec le futur webclient

Le module `acpec_fueltoken_company` contient uniquement le métier backend société.

Le futur module/espace `FuelToken_WebClient` ou `acpec_fueltoken_company_portal` devra contenir uniquement :

- contrôleurs HTTP/JSON web ;
- pages portail société ;
- formulaire de distribution ;
- historique et lecture des soldes.

Il ne doit pas dupliquer les règles de distribution. Il doit appeler les méthodes backend ci-dessus.

## Dépendances

- `mail`
- `portal`
- `acpec_mobile_auth`
- `acpec_fueltoken_base`
- `acpec_fueltoken_core`
- `acpec_fueltoken_purchase`
- `acpec_fueltoken_backoffice_ui`

## Installation / mise à jour

Installation :

```powershell
docker compose -f .\docker-compose19.yml run --rm -T odoo19_svc odoo `
  -c /etc/odoo/odoo.conf `
  -d fueltoken `
  -i acpec_fueltoken_company `
  --stop-after-init
```

Mise à jour :

```powershell
docker compose -f .\docker-compose19.yml run --rm -T odoo19_svc odoo `
  -c /etc/odoo/odoo.conf `
  -d fueltoken `
  -u acpec_fueltoken_company `
  --stop-after-init
```

## Tests recommandés

Cas acceptés :

- société `is_company = True` avec accès portail actif, sans groupe interne/mobile, avec membres individuels ;
- préparation wallets membres pour membres déjà mobiles actifs/approuvés ;
- distribution société active vers membre déclaré, mobile actif/approuvé, avec ligne de faces transférable.

Cas refusés :

- partenaire individu comme société ;
- société sans accès portail ;
- société liée à un utilisateur interne ;
- société liée à un utilisateur mobile FuelToken ;
- membre société dans la liste des membres ;
- transfert société vers non-membre ;
- transfert société vers membre sans compte mobile actif/approuvé ;
- transfert vers une société ;
- génération QR depuis un wallet société.


## Note Odoo 19 — groupes utilisateurs

Cette version évite les domaines ORM sur `res.users.groups_id`, car ce champ n’est pas
exposé comme champ recherchable dans l’environnement Odoo 19 testé. Les contrôles de
groupes passent donc par la table standard `res_groups_users_rel` pour vérifier :

- l’accès portail standard ;
- l’absence de groupes internes / mobile / station / back-office ;
- le statut mobile actif et approuvé des membres avant distribution.

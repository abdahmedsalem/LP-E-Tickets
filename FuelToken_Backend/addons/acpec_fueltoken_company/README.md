# ACPEC FuelToken Company Accounts

Module Odoo 19 pour gérer les **Comptes Sociétés** FuelToken dans le back-office ACPEC.

Version : `19.0.1.3.2`.

## Doctrine fonctionnelle

Un Compte Société est une entité séparée du flux mobile existant.

- **Mobile users** : flux mobile existant, APIs mobile inchangées.
- **Comptes Sociétés** : flux portail/web séparé.
- **Back-office ACPEC** : création, gestion, validation et audit.

Le module ne modifie pas les APIs mobile, ne crée pas de contrôleur mobile et ne change pas le comportement du signup mobile.

## Modèle métier

Le modèle principal est :

::

    acpec.fuel.distributor


Il représente la relation suivante :

::

    Compte Société
    = partner société avec accès portail Odoo standard
    + membres partenaires individuels


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

Mais une distribution vers ce membre est refusée tant que le membre n’a pas un utilisateur mobile FuelToken actif et éligible :

::

    res.users.active = True
    res.users.partner_id = membre
    res.users.company_ids contient company_id du Compte Société
    appartenance au groupe acpec_fueltoken_base.group_fuel_user vérifiée via res_groups_users_rel
    res.users.mobile_state in ('approved', 'self_registered')


La distribution société ne valide jamais automatiquement un compte mobile, ne change jamais `mobile_state` et n’ajoute jamais de groupe mobile.

## Backend distribution

Le module porte maintenant les méthodes backend de distribution société. Le futur espace web `FuelToken_WebClient` ou `acpec_fueltoken_company_portal` devra appeler ces méthodes au lieu de réimplémenter le métier.

Méthodes principales sur `acpec.fuel.distributor` :

::

    action_prepare_member_wallets()
    action_distribute_to_member(member_partner, lines, note=False, idempotency_key=False, confirm=True)
    action_distribute_bulk(distribution_lines, idempotency_key=False)


### Préparation wallets membres

`action_prepare_member_wallets()` crée les wallets techniques des membres qui ont déjà un compte mobile actif et éligible.

Elle ne valide pas les utilisateurs mobiles. Les membres non prêts sont signalés dans le chatter.

### Distribution vers un membre

`action_distribute_to_member(...)` crée et confirme un `acpec.fuel.carnet.transfer` standard :

::

    transfer = distributor.action_distribute_to_member(
        member_partner,
        [
            {'face_line_id': 10, 'carnet_qty': 1},
        ],
        note='Distribution mensuelle',
        idempotency_key='WEB-123',
    )


La méthode vérifie :

- le Compte Société est actif ;
- le partenaire société est toujours portal-only ;
- le destinataire est membre du Compte Société ;
- le destinataire est un membre individuel ;
- le destinataire a un compte mobile actif et éligible (`approved` ou `self_registered`) ;
- le wallet société existe ou est créé à la demande ;
- le wallet membre existe ou est créé à la demande ;
- les lignes source appartiennent au wallet société ;
- les lignes source sont transférables en carnets intacts ;
- l’idempotence est respectée via `idempotency_key`.

Le moteur de transfert reste celui du core : `acpec.fuel.carnet.transfer.action_confirm()`.


## Achat société depuis le back-office

Les listes opérationnelles back-office peuvent rester en **no create** conformément à la doctrine.
Pour créer une demande d’achat pour un Compte Société, utiliser le bouton dédié sur la fiche :

::

    Compte Société actif > Créer achat société


Ce bouton crée un `acpec.fuel.purchase` en brouillon avec :

::

    partner_id = partner société du Compte Société
    company_id = company_id du Compte Société


Il ouvre ensuite le formulaire achat standard pour que l’agent ACPEC ajoute les lignes de carnets,
la preuve de paiement et soumette/valide via le workflow existant.

Le bouton ne valide pas automatiquement l’achat, ne crédite pas le wallet directement et ne modifie
aucun flux mobile. La validation reste dans `acpec.fuel.purchase.action_approve()`.

## Garde-fous métier inclus

Le module contient aussi des garde-fous pour éviter que le Compte Société se comporte comme un utilisateur mobile :

- un Compte Société ne peut pas recevoir de transfert entrant manuel ;
- une société active peut distribuer uniquement vers ses membres ;
- une société suspendue, clôturée ou archivée ne peut pas distribuer ;
- une distribution vers un membre non mobile actif/éligible est refusée ;
- un Compte Société ne peut pas générer de QR ;
- un achat pour une société suspendue/clôturée est refusé au moment de la soumission si le hook `_check_before_submit` est appelé par le module achat.

Ces garde-fous ne modifient pas les APIs mobile.

## Back-office

Le menu est ajouté sous :

::

    FuelToken > Comptes Sociétés > Comptes Sociétés


La création est autorisée car il s’agit d’un objet d’onboarding.

La suppression est interdite. Il faut suspendre, clôturer ou archiver pour conserver la traçabilité.

Le bouton **Préparer wallets membres** est disponible sur un Compte Société actif.

## Séparation avec le futur webclient

Le module `acpec_fueltoken_company` contient uniquement le métier backend société.

Le module `acpec_fueltoken_company_portal` existe déjà et doit rester une interface fine appelant le contrat backend Patch34F. Tout futur `FuelToken_WebClient` devra respecter le même contrat et porter uniquement :

- contrôleurs HTTP/JSON web ;
- pages portail société ;
- formulaire de distribution ;
- historique et lecture des soldes.

Il ne doit pas dupliquer les règles de distribution. Il doit appeler les méthodes backend ci-dessus. En sélection explicite, il doit envoyer une ligne par carnet avec `face_line_id` et `carnet_qty = 1`.

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

::

    docker compose -f .\docker-compose19.yml run --rm -T odoo19_svc odoo `
      -c /etc/odoo/odoo.conf `
      -d fueltoken `
      -i acpec_fueltoken_company `
      --stop-after-init


Mise à jour :

::

    docker compose -f .\docker-compose19.yml run --rm -T odoo19_svc odoo `
      -c /etc/odoo/odoo.conf `
      -d fueltoken `
      -u acpec_fueltoken_company `
      --stop-after-init


## Tests recommandés

Cas acceptés :

- société `is_company = True` avec accès portail actif, sans groupe interne/mobile, avec membres individuels ;
- préparation wallets membres pour membres déjà mobiles actifs/éligibles ;
- distribution société active vers membre déclaré, mobile actif/éligible, avec carnet transférable.

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
- le statut mobile actif et éligible des membres avant distribution.

## Patch34F — Contrat Company Portal carnets

- Le futur Company Portal doit utiliser `face_line_id` comme clé technique du carnet source.
- En sélection explicite portail, une ligne représente un carnet source : `{'face_line_id': X, 'carnet_qty': 1}`.
- Pour distribuer plusieurs carnets, envoyer plusieurs lignes avec des `face_line_id` différents.
- Le champ `carnet_qty` reste conservé pour compatibilité backend/wizard, mais le portail ne doit pas l’utiliser pour regrouper plusieurs carnets sur un même `face_line_id`.
- Le portail ne doit pas créer directement les transferts ni modifier les wallets ; il doit appeler les méthodes backend de distribution.

## Version 1.4.0 — distribution back-office contrôlée

Cette version ajoute une surface back-office explicite pour distribuer des carnets depuis un Compte Société vers un membre.

Bouton ajouté sur `acpec.fuel.distributor` :

- **Distribuer carnets**

Le bouton ouvre un assistant modal qui :

- affiche les lignes de carnets intactes disponibles sur le wallet société ;
- permet de choisir uniquement un membre rattaché au Compte Société ;
- permet de saisir le nombre de carnets à transférer par ligne ;
- appelle la méthode backend `action_distribute_to_member()` ;
- crée un `acpec.fuel.carnet.transfer` via le moteur existant ;
- confirme immédiatement le transfert par défaut.

Règles conservées :

- le Compte Société doit être actif ;
- le membre doit appartenir à `member_partner_ids` ;
- le membre doit être un partenaire individuel ;
- le membre doit avoir un utilisateur mobile FuelToken actif et éligible (`approved` ou `self_registered`) ;
- le wallet membre peut être créé techniquement à la demande ;
- le compte mobile du membre n’est jamais approuvé automatiquement ;
- aucune API mobile n’est modifiée ;
- aucun portail write n’est ajouté dans cette version.

Cette action est une surface ACPEC back-office. Le futur `FuelToken_WebClient` devra appeler les mêmes méthodes backend au lieu de réimplémenter le métier.


## v1.4.1 — Correction assistant distribution Odoo 19

Correction de robustesse sur l’assistant de distribution back-office :

- `face_line_id` n’est plus `required=True` au niveau ORM sur la ligne transitoire ;
- les lignes avec quantité > 0 sont validées explicitement avant distribution ;
- le champ `face_line_id` est sauvegardé avec `force_save="1"` dans la vue ;
- les lignes transitoires vides ou incomplètes ne provoquent plus d’erreur technique `Missing required value`.

La règle métier ne change pas : toute ligne réellement distribuée doit toujours référencer un carnet source.

## v1.4.2 — Libellés Ticket dans la distribution société

- Les libellés visibles du wizard de distribution société utilisent **Ticket** au lieu de **Face**.
- Les noms techniques/API (`face_line_id`, `face_value`) restent inchangés pour ne pas casser les appels backend et mobile.


## 19.0.1.4.3

- Masque par défaut les colonnes redondantes `Tickets par carnet` et `Valeur du ticket` dans le wizard de distribution société.


### 19.0.1.4.4 — Distribution manuelle par type de carnet

- Le wizard de distribution société ne pré-remplit plus les lignes avec tous les soldes disponibles.
- L’opérateur saisit explicitement les types de carnets et les quantités à distribuer.
- Le choix du bénéficiaire interdit la création rapide, la création/édition et l’ouverture du contact depuis le wizard.
- Les colonnes techniques `Wallet` et `Carnet source` restent disponibles en audit mais sont masquées par défaut.
- Les colonnes redondantes `Tickets disponibles`, `Tickets par carnet`, `Valeur du ticket` et `Tickets à distribuer` sont masquées par défaut selon leur utilité métier.
- Les colonnes `Carnets à distribuer`, `Tickets à distribuer` et `Montant` affichent des totaux en bas de liste.
- Le backend alloue automatiquement les carnets demandés sur les lignes techniques disponibles du wallet société, par ordre d’expiration puis ID.

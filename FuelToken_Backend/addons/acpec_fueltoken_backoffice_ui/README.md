# ACPEC FuelToken Back-office UI

Module Odoo 19 destiné à améliorer l'ergonomie du back-office FuelToken sans modifier la logique métier existante.

## Objectif

Ce module fournit une première couche UI pour les opérateurs ACPEC : menus plus lisibles, libellés métier en français et accès rapides aux files de travail quotidiennes.

Il respecte les principes de la refonte FuelToken v3.2 :

- ne pas toucher au frontend mobile ;
- ne pas modifier les contrats des API mobile ;
- ne pas modifier les modèles métier FuelToken ;
- garder la logique métier dans les méthodes existantes ;
- préparer l'arrivée des futurs Comptes Sociétés sans créer encore le modèle société.

## Périmètre fonctionnel

Le menu FuelToken est réorganisé autour des usages back-office :

```text
FuelToken
├── Tableau de bord
├── Opérations du jour
│   ├── Nouveaux comptes mobiles à valider
│   ├── Achats à valider
│   ├── Dernières consommations
│   ├── Derniers transferts
│   └── Bons de retrait à surveiller
├── Clients & soldes
│   ├── Comptes clients
│   ├── Crédits disponibles
│   ├── Bons de retrait
│   └── Historique des mouvements
├── Comptes Sociétés
│   ├── Historique des transferts de carnets
│   └── Achats sociétés
├── Stations
│   ├── Stations-service
│   └── Consommations par station
├── Pilotage
└── Configuration
```

## Politique de création v1

Pour limiter les erreurs opérationnelles, la création manuelle est désactivée sur les écrans métier opérationnels et d'audit : achats, wallets, crédits disponibles, bons de retrait, transactions, transferts, sessions mobile et OTP.

La création reste autorisée sur les écrans de configuration ou d'onboarding :

- formules de carnet ;
- stations-service ;
- politiques mobile ;
- futurs Comptes Sociétés, quand le module `acpec_fueltoken_company` sera livré.

Cette limitation se fait uniquement au niveau des actions UI, via le contexte Odoo. Elle ne remplace pas les contrôles serveur et ne modifie pas les droits d'accès existants.

## Comptes Sociétés

Le menu `Comptes Sociétés` est préparé, mais le modèle technique `acpec.fuel.distributor` n'est pas encore créé par ce module.

Dans cette première version, le back-office ne réalise pas les transferts à la place de la société. L'entrée `Historique des transferts de carnets` sert uniquement à consulter/auditer les transferts existants. Le filtrage strict par compte société sera ajouté dans un module ultérieur.

## Modules dépendants

Ce module dépend de :

- `acpec_fueltoken_reports` ;
- `acpec_mobile_auth_otp`.

Les dépendances transitives FuelToken et Mobile Auth doivent donc être installées.

## Installation

1. Placer le module dans le dossier addons :

```text
FuelToken_Backend/addons/acpec_fueltoken_backoffice_ui
```

2. Vérifier que `addons_path` pointe vers le dossier `addons` :

```ini
addons_path = /mnt/extra-addons/github/FuelToken/FuelToken_Backend/addons
```

3. Redémarrer Odoo.
4. Mettre à jour la liste des applications.
5. Installer `ACPEC FuelToken Back-office UI`.

## Mise à jour

En ligne de commande :

```bash
odoo -c /etc/odoo/odoo.conf -d <base> -u acpec_fueltoken_backoffice_ui --stop-after-init
```

Ou depuis l'interface Odoo : Apps > ACPEC FuelToken Back-office UI > Upgrade.

## Vérifications recommandées

Après installation ou mise à jour :

- le menu `FuelToken` reste visible ;
- `Opérations du jour` contient les files de travail attendues ;
- `Nouveaux comptes mobiles à valider` apparaît dans `Opérations du jour` ;
- les anciens menus QR multiples sont masqués ;
- `Mobile Auth` n'apparaît plus comme application séparée ;
- les écrans opérationnels ne proposent pas le bouton `Nouveau` ;
- les boutons métier existants restent disponibles : valider, rejeter, révoquer, bloquer, etc.

## Limites connues

- `Tableau de bord` est provisoire : il pointe vers une action existante en attendant un vrai dashboard.
- `Comptes Sociétés` ne contient pas encore le vrai modèle société ; il sera alimenté par le futur module `acpec_fueltoken_company`.
- Les historiques liés aux sociétés ne sont pas encore filtrés strictement par société, car le modèle distributeur n'existe pas encore dans ce module.

## Non-objectifs

Ce module ne fait pas :

- de modification Flutter ;
- de modification des API mobile ;
- de modification de `res.partner` ;
- de création de `acpec.fuel.distributor` ;
- de gardes serveur société ;
- de web client société ;
- de changement de workflow métier.

## Roadmap associée

Les étapes suivantes prévues sont :

1. vues métier back-office plus contrôlées ;
2. module `acpec_fueltoken_company` pour les Comptes Sociétés ;
3. gardes serveur société ;
4. API portal société ;
5. pages web client société.

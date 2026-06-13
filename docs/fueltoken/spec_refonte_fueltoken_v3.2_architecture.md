# Spec d’architecture — Refonte FuelToken v3.2

## 0. Statut du document

Document de cadrage figé avant les patches de code.

Cette version remplace le cadrage v3/v3.1 pour les décisions d’architecture suivantes :

- le frontend mobile existant est hors chantier ;
- les APIs mobile existantes ne doivent pas être modifiées, sauf gardes serveur invisibles ;
- le back-office Odoo est amélioré comme outil interne ACPEC ;
- le web client société est une nouvelle surface séparée ;
- une société est un compte portal Odoo standard, créé par le back-office ;
- un compte société est reconnu uniquement par un enregistrement actif `acpec.fuel.distributor` ;
- le libellé UI retenu est **Compte Société / Comptes Sociétés** ;
- la société achète et distribue, mais ne consomme jamais ;
- la société ne suit pas le wallet ni les transactions de l’employé après transfert.

---

## 1. Principe directeur

FuelToken repose sur **un seul backend métier** et **trois surfaces séparées**.

| Surface | Utilisateurs | Authentification | Rôle |
|---|---|---|---|
| Mobile app | Particuliers, employés, stations | Token mobile `acpec.mobile.session` | Recevoir, consommer, transférer |
| Back-office Odoo | Opérateurs internes ACPEC | Session interne Odoo | Valider, onboarder, auditer, assister, configurer |
| Web client société | Comptes sociétés | Portal Odoo standard `auth='user'` | Acheter, distribuer, consulter son historique |

Principe non négociable : **un seul cerveau métier, plusieurs surfaces**.

La logique métier reste dans les modèles Odoo :

- `action_confirm` ;
- `action_approve` / `action_reject` ;
- `create_from_api` ;
- `issue_from_available` ;
- calculs de wallet ;
- verrous pessimistes ;
- idempotence ;
- transactions métier.

Les interfaces ne doivent pas réimplémenter les règles métier.

---

## 2. Frontend mobile — gelé

### 2.1 Décision

La mobile app existante est hors chantier.

Ne pas toucher :

- au frontend Flutter ;
- aux écrans mobile ;
- aux contrats des routes mobile ;
- aux payloads attendus par l’app mobile ;
- au transfert mobile générique ;
- aux APIs station existantes ;
- aux APIs mobile auth existantes, sauf gardes serveur invisibles.

### 2.2 Exception autorisée

On peut ajouter côté backend des gardes serveur qui ne changent pas le contrat API pour les utilisateurs normaux :

- refuser un token mobile à un compte société ;
- refuser l’utilisation d’un ancien token mobile si un partner devient compte société ;
- empêcher un compte société d’émettre un QR / bon de retrait ;
- empêcher un compte société de consommer.

### 2.3 Avocat du diable

Ne pas adapter le mobile pour les sociétés. Même une petite adaptation peut créer une dépendance avec l’équipe mobile externe et casser son avancement.

Le compte société est **web-only**.

---

## 3. Backend métier

Le backend Odoo est la source de vérité.

Il porte :

- les wallets ;
- les commandes de crédit ;
- les lignes de crédit ;
- les QR / bons de retrait ;
- les transferts ;
- les transactions métier ;
- les stations ;
- les comptes sociétés ;
- les règles de sécurité ;
- l’idempotence ;
- les validations métier.

Le backend doit rester stable : on ajoute les règles société, mais on ne refond pas la mécanique existante.

---

## 4. Compte Société

### 4.1 Nom UI

Utiliser dans l’interface :

- **Compte Société** ;
- **Comptes Sociétés**.

Ne pas utiliser “Sociétés distributrices” dans les menus visibles opérateurs.

### 4.2 Nom technique

Le modèle technique reste :

```python
acpec.fuel.distributor
```

### 4.3 Définition

Un Compte Société est :

- un partner société ;
- lié à un portal user Odoo standard ;
- créé uniquement par le back-office ;
- reconnu comme société distributrice uniquement par un enregistrement actif `acpec.fuel.distributor`.

### 4.4 Invariants

1. Aucun champ custom n’est ajouté à `res.partner`.
2. Un compte société est créé uniquement par le back-office.
3. Un utilisateur mobile existant ne peut pas devenir compte société.
4. Un compte société utilise le portal Odoo standard.
5. Un compte société n’utilise jamais le token mobile.
6. Un compte société achète des carnets.
7. Un compte société distribue des carnets à ses membres.
8. Un compte société ne consomme jamais.
9. Un compte société ne peut pas émettre de QR / bon de retrait.
10. Un employé est un utilisateur mobile normal.
11. Un employé peut être rattaché à une seule société.
12. Après réception d’un carnet, l’employé utilise son wallet indépendamment de la société.
13. La société ne suit pas le wallet privé de l’employé après distribution.

---

## 5. Employé / utilisateur mobile

Un employé :

- s’inscrit via la mobile app ;
- reste un utilisateur mobile normal ;
- peut être rattaché à un Compte Société par le back-office ;
- reçoit des carnets de la société ;
- après réception, utilise son wallet de manière indépendante ;
- peut consommer ;
- peut transférer librement via le mobile.

La société ne suit pas :

- ses QR / bons de retrait ;
- ses consommations ;
- ses transferts ultérieurs ;
- son solde privé.

---

## 6. Règles d’appartenance société / employés

À implémenter dans `acpec.fuel.distributor` :

- une société ne peut pas être son propre membre ;
- un employé ne peut appartenir qu’à une seule société ;
- un Compte Société ne peut pas être membre d’un autre Compte Société ;
- un utilisateur mobile existant ne peut pas devenir Compte Société ;
- le téléphone mobile des utilisateurs mobiles doit être unique et normalisé.

---

## 7. Back-office Odoo — rôle exact

Le back-office est l’outil interne ACPEC.

Il sert à :

1. valider les nouveaux comptes mobiles ;
2. valider les achats / commandes de crédit ;
3. créer les Comptes Sociétés ;
4. créer ou vérifier les portal users société ;
5. rattacher les employés ;
6. suivre les distributions ;
7. assister les clients ;
8. auditer les mouvements ;
9. gérer les stations ;
10. configurer les formules de carnet et les politiques mobile ;
11. piloter l’activité.

Le back-office ne doit pas devenir le web client société.

Une société cliente ne doit jamais entrer dans le back-office.

---

## 8. Back-office Odoo — menu cible

Menu cible :

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
│   ├── Comptes Sociétés
│   ├── Distributions sociétés
│   └── Achats sociétés
├── Stations
│   ├── Stations-service
│   └── Consommations par station
├── Pilotage
│   ├── Analyse des achats
│   ├── Analyse des consommations
│   ├── Analyse des distributions
│   └── Expirations à venir
└── Configuration
    ├── Formules de carnet
    ├── Politiques mobile
    ├── Sessions mobile
    ├── Vérifications OTP
    └── Paramètres
```

Point figé : **Nouveaux comptes mobiles à valider** doit être dans **Opérations du jour**, car c’est une file de travail opérationnelle.

L’historique complet des demandes de compte mobile peut rester accessible sous Configuration / Accès mobile.

---

## 9. Glossaire UI back-office

| Technique | UI opérateur |
|---|---|
| Wallet | Compte client / Solde |
| Face line | Crédit disponible |
| Face | Unité de crédit |
| QR | Bon de retrait |
| Purchase | Commande de crédit / Achat |
| Carnet type | Formule de carnet |
| Transaction | Historique / Mouvement |
| Transfer | Distribution / Transfert |
| Distributor | Compte Société |
| Mobile Session | Session mobile |
| OTP Challenge | Vérification OTP |
| Account Request | Nouveau compte mobile / Demande de compte mobile |

---

## 10. Back-office — travaux autorisés

### 10.1 Majoritairement XML

À faire sans toucher au métier :

- réorganisation des menus ;
- renommage des menus et actions ;
- filtres favoris ;
- group by ;
- statusbar ;
- badges ;
- masquage des champs techniques ;
- vue unique “Bons de retrait” avec filtres ;
- francisation de Mobile Auth ;
- amélioration des formulaires et listes.

### 10.2 Petit Python accepté seulement si nécessaire

Acceptable :

- smart buttons ;
- compteurs légers ;
- actions `action_open_*` ;
- contraintes du modèle Compte Société ;
- helpers distributeur ;
- gardes serveur.

### 10.3 À éviter

Ne pas faire :

- refonte profonde des modèles ;
- nouveau workflow inutile ;
- duplication de logique métier ;
- dashboards lourds dès le début ;
- mélange UI + sécurité + portal dans le même patch ;
- exposition aux opérateurs de `idempotency_key`, tokens, hash ou champs techniques.

---

## 11. Web client société

Le web client société est une nouvelle surface séparée.

### 11.1 Authentification

Le web client société utilise :

```python
auth='user'
```

Avec :

- login Odoo standard ;
- mot de passe Odoo standard ;
- reset password Odoo standard ;
- cookie/session Odoo ;
- portal user ;
- pas de token mobile ;
- pas de CORS si same-origin.

### 11.2 Fonctionnalités autorisées

Le web client société permet :

- consulter la cagnotte société ;
- acheter des carnets ;
- distribuer des carnets aux membres ;
- consulter les achats ;
- consulter l’historique des distributions.

### 11.3 Fonctionnalités interdites

Le web client société ne permet pas :

- créer des employés ;
- modifier les employés ;
- désactiver les employés ;
- consulter le solde privé d’un employé ;
- consulter les QR / bons de retrait d’un employé ;
- consulter les consommations d’un employé ;
- gérer les stations ;
- valider les achats.

### 11.4 Écrans cibles

1. Tableau de bord : cagnotte société, achats en attente, achats validés, carnets distribués, dernières distributions.
2. Acheter : formule de carnet, nombre de carnets, preuve de paiement, référence paiement, soumission.
3. Distribuer : membres, crédits disponibles société, nombre de carnets, confirmation, distribution batch atomique.
4. Historique : achats et distributions.

---

## 12. Modules cibles

Architecture recommandée :

```text
acpec_fueltoken_base
acpec_fueltoken_catalog
acpec_fueltoken_purchase
acpec_fueltoken_core
acpec_fueltoken_api              # API mobile/station/admin existante
acpec_mobile_auth
acpec_mobile_auth_otp

NOUVEAU :
acpec_fueltoken_backoffice_ui    # refonte menus/vues, majoritairement XML
acpec_fueltoken_company          # Comptes Sociétés + règles serveur
acpec_fueltoken_company_portal   # web client société + endpoints company/*
```

| Module | Rôle |
|---|---|
| `acpec_fueltoken_backoffice_ui` | Améliorer l’UX back-office sans changer le métier |
| `acpec_fueltoken_company` | Modèle `acpec.fuel.distributor`, contraintes, gardes serveur, vues Compte Société |
| `acpec_fueltoken_company_portal` | Routes portal, pages web société, endpoints `company/*` |

Les endpoints société ne doivent pas être ajoutés dans les APIs mobile existantes.

---

## 13. Roadmap depuis zéro

### Patch 0 — Spec architecture v3.2

Documenter officiellement cette architecture.

### Patch 1 — Back-office UI légère

Objectif : amélioration user-friendly sans métier.

Contenu :

- nouveau module `acpec_fueltoken_backoffice_ui` ;
- menus ;
- noms UI ;
- regroupements ;
- filtres opérationnels ;
- francisation ;
- masquage des anciens menus techniques redondants ;
- “Nouveaux comptes mobiles à valider” dans Opérations du jour.

### Patch 2 — Vues métier back-office

Objectif : rendre les écrans plus exploitables.

Contenu :

- achats à valider ;
- comptes clients ;
- crédits disponibles ;
- bons de retrait ;
- historique des mouvements ;
- transferts ;
- stations.

### Patch 3 — Module `acpec_fueltoken_company`

Objectif : créer les Comptes Sociétés.

Contenu :

- modèle `acpec.fuel.distributor` ;
- contraintes ;
- membres ;
- vues Compte Société ;
- smart buttons.

### Patch 4 — Gardes serveur société

Objectif : sécurité.

Contenu :

- bloquer token mobile société ;
- bloquer ancien token mobile société ;
- bloquer QR / consommation société ;
- empêcher mobile user existant → Compte Société.

### Patch 5 — API portal société lecture

Endpoints :

- `company/me` ;
- `company/dashboard` ;
- `company/contacts` ;
- `company/carnet-types` ;
- `company/purchases` ;
- `company/distributions`.

### Patch 6 — API portal société écriture

Endpoints :

- `company/purchases/create` ;
- `company/distribute` ;
- `company/distribute_batch`.

### Patch 7 — Pages web client société

Écrans :

- tableau de bord ;
- acheter ;
- distribuer ;
- historique.

### Patch 8 — Reporting / pilotage

Après stabilisation :

- graph ;
- pivot ;
- export ;
- statistiques.

---

## 14. Décisions figées

1. Mobile app gelée.
2. Pas de modification des contrats API mobile.
3. Back-office Odoo amélioré en priorité UI/XML.
4. Nouveau web client société séparé.
5. Compte Société créé uniquement par back-office.
6. Compte Société = `acpec.fuel.distributor` actif.
7. Libellé UI : **Comptes Sociétés**.
8. Pas de champ ajouté à `res.partner`.
9. Société via portal Odoo standard.
10. Jamais de token mobile pour société.
11. Société achète et distribue, ne consomme jamais.
12. Société ne suit pas les transactions employé après transfert.
13. Nouveaux comptes mobiles à valider dans **Opérations du jour**.
14. Les champs techniques restent cachés aux opérateurs.

---

## 15. Avocat du diable — garde-fous

Refuser les dérives suivantes :

1. utiliser Flutter mobile pour le web société ;
2. mettre les endpoints société dans l’API mobile existante ;
3. donner aux sociétés un accès back-office ;
4. suivre le wallet privé des employés dans le web société ;
5. modifier les modèles métier pour un simple renommage UI ;
6. mélanger refonte UI, sécurité distributeur et portail société dans le même patch.

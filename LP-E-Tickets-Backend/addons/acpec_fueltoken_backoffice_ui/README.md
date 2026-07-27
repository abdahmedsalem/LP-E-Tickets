# ACPEC FuelToken Back-office UI

Module d'ergonomie back-office pour FuelToken.

## Objectif

Ce module réorganise les menus FuelToken et applique la doctrine back-office ACPEC sans modifier les modèles métier, les workflows de validation, les contrôleurs ou les API mobile.

## Doctrine appliquée

### 1. No create / no delete sur l'opérationnel

Les écrans opérationnels et d'audit ne doivent pas servir à créer ou supprimer manuellement les objets métier sensibles.

Exemples :

- achats à valider ;
- crédits disponibles ;
- bons de retrait ;
- transferts de carnets ;
- mouvements ;
- sessions mobile ;
- OTP ;
- demandes de comptes mobile.

La création reste autorisée sur les objets d'onboarding/configuration : formules de carnet, stations, comptes sociétés, politiques mobile.

### 2. Pas de domaines rigides pour les menus métier

Les menus métier comme **Achats à valider**, **Demandes d’inscription mobile**, **Dernières consommations**, **Bons de retrait à surveiller** et **Crédits disponibles** utilisent maintenant des filtres par défaut (`search_default_*`) au lieu de domaines rigides sur l'action.

Conséquence : l'utilisateur ouvre l'écran avec le bon filtre, mais peut retirer ce filtre depuis la barre de recherche pour consulter l'historique complet selon ses droits.

### 3. Sécurité hors UX

Les restrictions réelles doivent rester dans les groupes, les ACL et les règles d'accès (`ir.rule`). Les filtres d'action sont seulement de l'ergonomie.

## Contenu technique

Le module ajoute :

- des search views back-office dédiées ;
- des actions avec filtres par défaut ;
- des menus métier FuelToken ;
- des libellés français ;
- la désactivation de la création/suppression sur les vues opérationnelles.

Il ne touche pas :

- aux API mobile ;
- au signup mobile ;
- à Flutter ;
- aux modèles métier FuelToken ;
- aux méthodes de validation ;
- aux règles SQL.

## Version

`19.0.1.3.4`

Correction principale : remplacement des domaines rigides des actions back-office par des filtres par défaut retirables.

## v1.3 — Utilisateurs mobiles à valider

Historique : cette version a ajouté un menu **Opérations du jour > Utilisateurs mobiles en attente** sur `res.users`.

Cette orientation a été revue en v1.3.4, car les utilisateurs mobiles FuelToken sont validés automatiquement par OTP.


## v1.3.1 — Correctif ordre de chargement Odoo

Le fichier `mobile_users_backoffice_views.xml` est chargé avant `backoffice_menu_views.xml`, car le menu `Utilisateurs mobiles en attente` référence l'action `action_today_mobile_users_to_approve` définie dans ce fichier. Cela évite l'erreur `External ID not found` lors de la mise à jour du module.


## v1.3.3 — Libellés et visibilité des menus mobile

Clarifie les deux menus mobile :

- **Demandes d’inscription mobile** : ouvre `acpec.mobile.auth.account.request`. Ce menu reste réservé au groupe `acpec_mobile_auth.group_mobile_auth_admin`, car il porte le flux d’inscription / audit mobile.
- **Utilisateurs mobiles en attente** : ouvre `res.users` avec le filtre par défaut `mobile_state = pending`. Ce menu ne doit plus être utilisé comme opération métier ; le back-office FuelToken est réservé à `group_fuel_admin`.

La règle UX reste : filtre par défaut retirables, pas de domaine rigide.


## v1.3.4 — Doctrine mobile OTP et audit utilisateurs

Révision de doctrine :

- les utilisateurs mobiles sont validés automatiquement via OTP ;
- le menu opérationnel **Utilisateurs mobiles en attente** est neutralisé et réservé à `base.group_no_one` pour éviter une validation manuelle métier depuis `res.users` ;
- la liste **Configuration > Utilisateurs mobiles — audit** reste disponible pour support/audit uniquement, avec accès réservé à `acpec_mobile_auth.group_mobile_auth_admin` et `acpec_fueltoken_base.group_fuel_admin` ;
- les actions serveur historiques de validation/rejet/remise en attente sur `res.users` sont déliées du menu Action et remplacées par un message d'arrêt ;
- **Demandes d’inscription mobile** reste visible seulement pour `acpec_mobile_auth.group_mobile_auth_admin`.

La doctrine finale est : mobile = OTP automatique ; portail FuelToken Société = portail Odoo classique + `acpec.fuel.distributor` actif.

## v1.3.5 — Libellés Ticket et code public technique

- Le vocabulaire back-office privilégie désormais **Ticket** au lieu de **Face**.
- Les noms techniques Python/API (`face_line_id`, `face_value`, `public_code`) ne sont pas renommés afin de ne pas casser l’application mobile ni les intégrations.
- `Code public` est retiré des listes principales et déplacé en bas des formulaires dans une section technique.

## Version 19.0.1.3.6

Correction Odoo 19 : les héritages de vues ne sélectionnent plus les pages ou groupes avec `@string`, car Odoo refuse `string` comme sélecteur XPath. Les libellés Ticket restent inchangés ; seuls les sélecteurs techniques ont été sécurisés.



## 19.0.1.3.7

- Masque par défaut les colonnes redondantes `Tickets par carnet` et `Valeur du ticket` dans les listes où le type de carnet porte déjà l'information métier.

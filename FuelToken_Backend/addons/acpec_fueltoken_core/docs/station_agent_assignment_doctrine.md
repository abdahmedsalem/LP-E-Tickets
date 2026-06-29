# Doctrine affectation agents station — V1/V2

## V1

`user_id` sur `acpec.fuel.station` est conservé comme utilisateur station principal legacy.

En V1, il sert à :
- conserver la compatibilité des stations existantes ;
- synchroniser une affectation agent primaire `is_primary=True` ;
- garder un point d’ancrage stable pour les vues et usages historiques.

Il ne doit pas être interprété comme la liste complète des opérateurs de station.

`agent_ids` est la source métier pour les affectations agents station :
- une station peut avoir plusieurs agents ;
- un agent peut avoir des affectations historiques inactives ;
- une affectation active représente un lien BO user ↔ station.

`active_agent_ids` est une vue des affectations actives administrativement.
Ce n’est pas une preuve d’accès runtime.

Un agent est éligible à l’affectation station si :
- `res.users.active = True` ;
- `mobile_state in ('self_registered', 'approved')` ;
- il a le rôle Mobile Auth User ;
- il a le rôle Tickets Carburant - Station ;
- il n’est pas utilisateur interne Odoo, public ou admin BO FuelToken ;
- il n’a pas de wallet client non vide ;
- il appartient à la société de la station ;
- il n’est pas actif sur une autre station au même moment.

Un agent est opérationnel runtime seulement si, en plus :
- la station est active ;
- l’affectation est effective selon ses dates ;
- le device courant est trusted ;
- la session mobile est active.

Les notions “agent éligible” et “agent opérationnel” sont des règles backend dérivées.
Elles ne sont pas des statuts métier modifiables dans l’UI V1.

## V2

`user_id` pourra devenir le responsable station / superviseur station.
Usage potentiel V2 :
- voir les consommations de tous les agents de sa station ;
- reporting station consolidé ;
- supervision sans nécessairement être le seul opérateur.

# Doctrine affectation agents station — V1/V2

## Concepts

`agent_ids` sur `acpec.fuel.station` représente les agents opérationnels
autorisés à consommer pour une station.

`user_id` sur `acpec.fuel.station` représente le responsable / superviseur
station. Ce responsable est optionnel : une station peut avoir des agents
opérationnels sans responsable désigné.

Pour compatibilité V1, `user_id` reste aussi le point d’ancrage historique de
l’utilisateur station principal lorsqu’il existe.

Le responsable station, s’il existe, est aussi un agent opérationnel actif de
sa station : il peut consommer comme les autres agents. Sa différence métier est
la supervision : il pourra voir les consommations de tous les agents de sa
station dans les flux V2.

Les agents ordinaires ne partagent pas cette visibilité superviseur. Ils
restent limités à leurs propres consommations.

## V1

En V1, `user_id` sert à :
- conserver la compatibilité des stations existantes ;
- identifier le responsable station courant lorsqu’il est désigné ;
- synchroniser une affectation agent primaire `is_primary=True` ;
- garder un point d’ancrage stable pour les vues et usages historiques.

Il ne doit pas être interprété comme la liste complète des opérateurs de
station. La liste métier des opérateurs est portée par `agent_ids`.

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

Les notions “agent éligible” et “agent opérationnel” sont des règles backend
dérivées. Elles ne sont pas des statuts métier modifiables dans l’UI V1.

## V2

En V2, `user_id` doit être compris comme responsable / superviseur station :
- voir les consommations de tous les agents de sa station ;
- reporting station consolidé ;
- supervision sans être le seul opérateur.

Un agent ordinaire reste limité à ses propres consommations.

## Wizard BO

Le wizard BO “Ajouter agent station” affecte un utilisateur `mobile_only`
existant à une station par saisie de téléphone.

Il ne crée jamais d’utilisateur mobile.

Si l’option “Définir comme responsable station” est cochée, le wizard :
- ajoute l’utilisateur comme agent actif si nécessaire ;
- ajoute le rôle Station si nécessaire ;
- écrit `station.user_id = user`.

Si l’option n’est pas cochée, le wizard :
- ajoute l’utilisateur comme agent actif si nécessaire ;
- ajoute le rôle Station si nécessaire ;
- ne modifie pas `station.user_id`.

Le wizard refuse de remplacer un responsable station existant par un autre
utilisateur. Ce changement devra passer par une action dédiée.

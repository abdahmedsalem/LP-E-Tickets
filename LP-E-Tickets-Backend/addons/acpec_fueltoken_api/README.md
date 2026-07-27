# ACPEC FuelToken API

Module FuelToken conforme à la doctrine actuelle : lot d’achat → carnets individualisés → QR → consommation station.

Licence : OPL-1.
Auteur : ACPEC SARL.
Site : https://acpec.odoorim.com.

## Breaking change audit achat — transaction_type

Le type historique `achat_carnets` est supprimé volontairement du contrat API pendant la phase de développement. Les clients mobiles et back-office ne doivent plus l'utiliser comme filtre ou type métier.

Nouveaux types d'événements achat :

- `purchase_submitted` : demande d'achat soumise ; aucune valeur carburant n'est encore créée, aucun ticket n'est crédité.
- `purchase_approved` : achat approuvé ; les tickets sont réellement créés et le wallet est crédité.

Cette séparation est volontaire : une soumission d'achat n'est pas une création de valeur carburant. Les anciens filtres `achat_carnets` doivent être corrigés côté application mobile au lieu d'être maintenus en compatibilité silencieuse.

## Patch 2.2 — garde API `transaction_type`

La route mobile `/api/acpec/fueltoken/v1/mobile/transactions` accepte désormais un filtre optionnel `transaction_type`.

Le type historique `achat_carnets` est volontairement refusé avec le code d'erreur `OBSOLETE_TRANSACTION_TYPE`, car il a été scindé en deux événements distincts :

- `purchase_submitted` : demande d'achat soumise, sans valeur carburant créée ;
- `purchase_approved` : achat approuvé, tickets créés et valeur carburant disponible.

Un type inconnu est refusé avec `UNKNOWN_TRANSACTION_TYPE` au lieu de retourner silencieusement un historique vide.

## Patch 2.3 — pagination et filtres date des listes historiques

Les endpoints historiques acceptent désormais une pagination explicite et des filtres de dates quand le volume peut grossir.

Paramètres communs ajoutés selon endpoint :

- `limit` : nombre de lignes retournées ; borné côté serveur ;
- `offset` : décalage de pagination ;
- `date_from` / `date_to` : plage de dates inclusive ;
- `state` ou `transaction_type` selon le métier de la liste.

Réponse standard des listes paginées :

- `items` ;
- `count` : total après application des filtres ;
- `limit` : limite réellement appliquée par le backend ;
- `offset` : décalage courant ;
- `has_more` : indique s'il existe une page suivante ;
- `next_offset` : prochain offset à utiliser si `has_more=true`, sinon `null`.

Endpoints concernés :

- `/api/acpec/fueltoken/v1/mobile/purchases` : `limit=20`, `max=100`, filtre date sur `submitted_at`, filtre `state` optionnel ;
- `/api/acpec/fueltoken/v1/mobile/qr/list` : `limit=50`, `max=100`, filtre date sur `create_date`, filtre `state` optionnel ;
- `/api/acpec/fueltoken/v1/mobile/carnets/transfers` : `limit=20`, `max=100`, filtre date sur `create_date`, filtres `direction` et `state` optionnels ;
- `/api/acpec/fueltoken/v1/station/transactions` : `limit=20`, `max=200`, filtre date sur `create_date`, filtre `transaction_type` optionnel ;
- `/api/acpec/fueltoken/v1/admin/purchases/pending` : `limit=50`, `max=200`, filtre date sur `submitted_at`, filtre `state` optionnel.

Les référentiels faibles volumes, notamment les types de carnets, ne sont pas paginés volontairement : ils restent retournés en liste complète active.


## Patch 2.4 — `next_offset` pour pagination frontend

Les endpoints paginés retournent désormais `next_offset` afin que le frontend n'ait pas à recalculer la page suivante ni à deviner la limite réellement appliquée par le backend.

Règle d'utilisation côté client :

- première requête : `offset=0` ;
- si `has_more=true`, appeler la même route avec les mêmes filtres et `offset=next_offset` ;
- si `has_more=false`, `next_offset=null` et il n'y a plus de page à charger.

Exemple : une requête avec `limit=20`, `offset=0` et 73 lignes filtrées retourne `next_offset=20`. La page suivante utilisera `offset=20`.

## Patch 2.4.1 — cohérence des helpers API

Les helpers de pagination, plage de dates et filtre `transaction_type` sont centralisés dans `AcpecFuelTokenApiCommon`, base commune propre au module API FuelToken. Les contrôleurs mobile, station et admin utilisent la même source de vérité.

Conséquences contractuelles :

- `transaction_type=achat_carnets` est refusé partout où le filtre est supporté avec `OBSOLETE_TRANSACTION_TYPE` et un hint vers `purchase_submitted` / `purchase_approved` ;
- un type inconnu est refusé avec `UNKNOWN_TRANSACTION_TYPE` ;
- `transaction_type=all` et l'absence de `transaction_type` signifient uniformément « aucun filtre » ;
- les réponses paginées restent des objets contenant au minimum `items`. Les champs `count`, `limit`, `offset`, `has_more` et `next_offset` sont des métadonnées ajoutées pour la pagination et ne remplacent pas `items`.

Note de compatibilité frontend : le patch 2.3/2.4 ajoute des métadonnées à plusieurs endpoints historiques déjà enveloppés dans `items`; il ne transforme pas un tableau nu en objet. L'équipe mobile doit néanmoins lire `next_offset` pour les chargements successifs et ne plus utiliser `achat_carnets`.

## Patch 2.4.2 — pagination contract-safe

Le patch 2.4.2 corrige la compatibilité frontend : les endpoints déjà consommés gardent leur forme de réponse historique par défaut. Les nouveaux filtres `limit`, `offset`, `date_from`, `date_to`, `state` et `transaction_type` restent disponibles, mais les métadonnées enrichies de pagination ne sont retournées que si le client les demande explicitement avec::

    {
      "include_pagination_meta": true
    }

Formes conservées par défaut :

- `/mobile/purchases` : retourne `items` seulement, comme avant ; limite par défaut conservée à 50.
- `/mobile/qr/list` : retourne `items` seulement, comme avant ; limite par défaut conservée à 50.
- `/mobile/carnets/transfers` : conserve `items`, `count`, `limit`, `offset`, `has_more`; `next_offset` seulement sur opt-in.
- `/mobile/transactions` : conserve `items`, `count`, `limit`, `offset`, `has_more`; `next_offset` seulement sur opt-in.
- `/station/transactions` : conserve `station`, `items`, `count`, `limit`, `offset`, `has_more`; `next_offset` seulement sur opt-in.
- `/admin/purchases/pending` : conserve `items`, `count`; `limit`, `offset`, `has_more`, `next_offset` seulement sur opt-in.

Quand `include_pagination_meta=true`, le client reçoit la pagination complète :

- `count` : total après filtres ;
- `limit` : limite effectivement appliquée ;
- `offset` : offset courant ;
- `has_more` : indique s'il existe une page suivante ;
- `next_offset` : prochain offset à utiliser, ou `null` si dernière page.

Cette approche permet à l'équipe mobile de migrer écran par écran sans rupture brutale du contrat existant.

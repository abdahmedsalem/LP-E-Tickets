# Patch43H2B — contrat rôle station et Code QR numérique

## Décision

Un QR émis est un **titre de retrait porteur**.

La confiance du device client est exigée à l'émission du QR, pas à sa consommation.

La consommation station dépend uniquement :

- du device station trusted ;
- du rôle station ;
- de l'action sensible station `station_qr_use` ;
- de l'`idempotency_key` station ;
- de la validité du QR ;
- de l'état métier du QR ;
- de la société/station ;
- du verrouillage et de l'idempotence côté QR/transaction.

La révocation ou perte de trust du device client bloque les futures actions mobiles du client,
mais ne rend pas automatiquement non consommables les QR déjà émis.

Un QR déjà émis doit être bloqué par son propre état métier :

- `blocked` ;
- `expired` ;
- `consumed` ;
- ou une action explicite de blocage/sécurité.

## Identifiants

La station consomme un QR uniquement par l'un des deux identifiants suivants :

- `public_code` : code public issu du scan QR graphique ;
- `qr_numeric_code` : Code QR numérique manuel, 12 chiffres affichés en groupes de 4.

La station ne consomme jamais par :

- `acpec_human_code` ;
- `mobile_phone` ;
- `login` ;
- `partner_id` ;
- `res.users.id`.

## Invariant H2B

`check_qr` et `use_qr` doivent accepter exactement un identifiant QR :

- soit `public_code` ;
- soit `qr_numeric_code` ;
- jamais les deux ;
- jamais aucun des deux.

## Contrat endpoint station V1

Endpoints station autorisés :

- `/api/acpec/fueltoken/v1/station/profile`
- `/api/acpec/fueltoken/v1/station/qr/check`
- `/api/acpec/fueltoken/v1/station/qr/use`
- `/api/acpec/fueltoken/v1/station/transactions`

Les endpoints station ne doivent pas exposer :

- approbation achat ;
- approbation device ;
- gestion station ;
- gestion type carnet ;
- génération QR client ;
- transfert carnet ;
- rapports back-office ;
- consommation par code utilisateur humain.

## Idempotence

`use_qr` est une action sensible station.

Le hash d'idempotence doit être canonique :

- résolution du QR par `public_code` ou `qr_numeric_code` ;
- remplacement par le `public_code` canonique avant calcul du hash ;
- suppression de `qr_numeric_code` du payload hashé.

Cela évite qu'une même consommation par scan et par saisie manuelle devienne deux opérations différentes.

## Raison métier

Un client peut créer un QR puis l'envoyer à un chauffeur ou à une personne qui n'a pas l'application.
Le QR doit rester consommable si son état métier est valide.

Exiger le device trusted du propriétaire au moment de la consommation casserait la confiance dans le QR généré.

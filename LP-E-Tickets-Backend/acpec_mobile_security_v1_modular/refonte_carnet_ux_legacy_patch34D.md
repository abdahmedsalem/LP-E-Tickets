# Refonte carnet UX / legacy - Patch34D

## Contexte

Patch34A a fixé la doctrine :

1 acpec.fuel.face.line = 1 carnet.

Patch34B a rendu l’émission QR explicite par face_line_id.

Patch34C a corrigé le transfert intact de carnet : le même carnet est déplacé vers le wallet destinataire, sans création de copie.

Patch34D est un patch de cohérence UX et documentation. Il ne modifie pas les règles métier.

## Objectif

Supprimer les anciens libellés visibles hérités du modèle agrégé :

- Ligne de faces ;
- Lignes de faces ;
- Ligne de tickets ;
- Ligne de tickets source ;
- Ligne de tickets destination ;
- faces disponibles quand le contexte parle des carnets disponibles.

Ces termes sont remplacés par des libellés métier alignés avec la doctrine actuelle :

- Carnet ;
- Carnets ;
- Carnet source ;
- Carnet destination ;
- tickets disponibles quand il s’agit d’une quantité de tickets/faces.

## Principe conservé

Les noms techniques ne sont pas renommés.

Sont volontairement conservés :

- face_line_id ;
- dest_face_line_id ;
- face_line_ids ;
- acpec.fuel.face.line.

Ces noms restent stables pour éviter de casser :

- l’API mobile ;
- les tests ;
- les intégrations ;
- les migrations futures ;
- les références techniques internes.

## Changements UX

Patch34D met à jour les libellés visibles dans :

- wallet ;
- QR ;
- transactions ;
- transfert de carnets ;
- distribution société ;
- surcharge back-office UI ;
- catalogue de test API ;
- README des modules concernés.

Exemples :

- Ligne de faces source devient Carnet source ;
- Ligne de faces dest. devient Carnet destination ;
- Ligne de tickets devient Carnet ;
- Lignes de faces devient Carnets ;
- Lister les faces disponibles devient Lister les carnets disponibles.

## Legacy transfer helper

La méthode credit_transferred() est conservée.

Elle est maintenant explicitement documentée comme helper legacy.

Depuis Patch34C, elle ne doit plus être utilisée pour les transferts de carnets intacts.

Les transferts de carnets intacts doivent déplacer la même face_line vers le wallet destinataire.

## Limites volontaires

Patch34D ne fait pas de renommage technique.

Patch34D ne supprime pas credit_transferred().

Patch34D ne modifie pas :

- la génération des carnets ;
- l’émission QR ;
- le transfert mobile ;
- l’idempotency ;
- l’action_code ;
- la trusted-device policy ;
- la logique de distribution.

## Validation

Validation réalisée le 23/06/2026.

Contrôles réalisés :

- py_compile sur les fichiers Python modifiés ;
- git diff --check ;
- test élargi Odoo avec mise à jour des modules core/api/company/backoffice_ui/test.

Résultat test élargi :

- 103 post-tests ;
- 0 failed ;
- 0 error.

Périmètre validé :

- chargement des modèles ;
- chargement des vues XML ;
- cohérence des libellés visibles ;
- absence de régression sur les tests core/api/test existants.

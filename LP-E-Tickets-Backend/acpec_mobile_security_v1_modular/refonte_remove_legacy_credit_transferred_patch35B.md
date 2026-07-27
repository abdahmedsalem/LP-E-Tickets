# Patch35B — Suppression du helper legacy credit_transferred

## Objet

Patch35B supprime la méthode legacy `credit_transferred()` de `acpec.fuel.face.line`.

Cette méthode avait été conservée temporairement pendant Patch34C / Patch34D pour compatibilité historique, mais elle n'a plus d'appelant métier actif.

## Décision

La méthode est supprimée car elle contredit la doctrine carnet individualisé :

- `1 acpec.fuel.face.line = 1 carnet`
- `wallet_id` représente uniquement le détenteur courant
- un transfert de carnet intact déplace la même `face_line`
- aucun transfert ne doit créer ou fusionner une ligne de carnet destination

## Risque supprimé

L'ancien helper pouvait :

- réutiliser une `face_line` destination par `(purchase_line_id, wallet_id)`
- augmenter `qty_initial`
- augmenter `qty_available`
- créer une nouvelle `face_line` sans identité carnet individualisée

Cela pouvait recréer un comportement consolidé incompatible avec :

- `carnet_no`
- `lot_short_code`
- `carnet_short_code`
- `carnet_sequence`

## Contrat maintenu

Les transferts valides restent ceux de Patch34C :

- même `face_line.id`
- même identité carnet
- changement de `wallet_id` vers le détenteur destinataire
- historique porté par les transactions / transferts

## Validation attendue

- aucun appel Python restant à `credit_transferred`
- compilation Python OK
- tests transfert / API / core OK

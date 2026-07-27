# Refonte transfert de carnet intact - Patch34C

## Contexte

Patch34A a fixé la nouvelle granularité métier :

1 acpec.fuel.face.line = 1 carnet.

Patch34B a ensuite permis l’émission QR par sélection explicite de carnet via face_line_id.

Avant Patch34C, le transfert de carnets utilisait encore l’ancien modèle agrégé :

- la face_line source était vidée ;
- une nouvelle face_line destination était créée ;
- dest_face_line_id pointait vers cette copie.

Ce comportement n’est plus compatible avec la doctrine Patch34A, car il duplique l’identité du carnet.

## Doctrine Patch34C

Un transfert de carnet intact doit déplacer le détenteur courant du carnet.

Le champ wallet_id de acpec.fuel.face.line représente le détenteur actuel du carnet.

Le transfert ne doit donc pas créer une nouvelle face_line destination.

Comportement retenu :

- même face_line ;
- même carnet_no ;
- même lot_short_code ;
- même carnet_short_code ;
- même carnet_sequence ;
- même purchase_id / purchase_line_id ;
- même expiration ;
- mêmes quantités ;
- wallet_id déplacé du wallet source vers le wallet destinataire.

## Règle d’intégrité

Patch34C autorise uniquement le transfert d’un carnet intact.

Conditions obligatoires :

- source_wallet_id != dest_wallet_id ;
- qty_available == qty_initial ;
- qty_qr_active == 0 ;
- qty_qr_blocked == 0 ;
- qty_consumed == 0 ;
- qty_expired == 0 ;
- le carnet n’est pas expiré ;
- la face_line appartient au wallet source ;
- le transfert porte sur la totalité du carnet.

La règle source_wallet_id != dest_wallet_id est protégée à deux niveaux :

- contrainte modèle _check_wallets ;
- garde explicite dans action_confirm.

Après Patch34A, cela correspond normalement à :

- carnet_qty = 1 ;
- qty_faces = face_count ;
- qty_initial = face_count.

## Compatibilité dest_face_line_id

Le champ dest_face_line_id est conservé pour compatibilité historique.

Mais après Patch34C :

dest_face_line_id = face_line_id

Il ne pointe plus vers une copie. Il pointe vers la même face_line déplacée vers le wallet destinataire.

## Journalisation

Le transfert continue à créer deux transactions :

- une transaction côté wallet source ;
- une transaction côté wallet destination.

Les lignes de transaction source et destination pointent toutes les deux vers la même face_line.

Cela permet de conserver l’audit source/destination sans dupliquer le carnet.

## API mobile

L’API de transfert conserve le contrat existant :

POST /api/acpec/fueltoken/v1/mobile/carnets/transfer

Payload :

{
  "recipient_phone": "...",
  "lines": [
    {"face_line_id": 101, "carnet_qty": 1}
  ],
  "action_code": "1234",
  "idempotency_key": "..."
}

Le payload de réponse expose maintenant aussi l’identité carnet :

- face_line_id ;
- dest_face_line_id ;
- carnet_no ;
- carnet_short_code ;
- lot_short_code ;
- carnet_sequence.

## Limites volontaires

Patch34C ne supprime pas la méthode legacy credit_transferred().

Elle est conservée provisoirement pour éviter une rupture sur d’éventuels anciens flux.

Patch34C ne traite pas encore :

- nettoyage final de la méthode legacy ;
- refonte UX back-office complète ;
- libellés finaux des vues ;
- transfert partiel d’une ancienne face_line agrégée ;
- migration de données historiques avant Patch34A.

## Validation

Validation réalisée le 23/06/2026.

Test ciblé transfert :

- TestCarnetTransferRuntimePolicy ;
- 7 post-tests ;
- 0 failed ;
- 0 error.

Test élargi core/api/company :

- 103 post-tests ;
- 0 failed ;
- 0 error.

Périmètre validé :

- transfert mobile avec action_code ;
- idempotency_key obligatoire ;
- replay idempotent ;
- conflit idempotency_key / payload rejeté ;
- trusted device obligatoire ;
- liste des transferts limitée à la société courante ;
- rejet défensif d’un transfert vers le même wallet ;
- déplacement de la même face_line vers le wallet destinataire ;
- conservation de l’identité carnet ;
- compatibilité dest_face_line_id ;
- absence de régression sur core/api/company.

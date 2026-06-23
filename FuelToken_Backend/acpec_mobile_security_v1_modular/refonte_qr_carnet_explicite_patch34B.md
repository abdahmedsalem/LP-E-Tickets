# Refonte QR par selection explicite de carnets - Patch34B

## Contexte

Patch34A a transforme la granularite de acpec.fuel.face.line :

1 face_line = 1 carnet.

Avant Patch34B, l'emission d'un QR utilisait encore une allocation automatique par carnet_type_id ou face_value. Le backend choisissait lui-meme les lignes disponibles selon une logique FIFO.

Patch34B ajoute la possibilite d'emettre un QR a partir de carnets explicitement choisis par le mobile ou par tout appelant backend.

## Doctrine retenue

Un QR peut maintenant etre emis a partir d'une selection explicite de carnets :

- face_line_id identifie le carnet choisi ;
- qty indique le nombre de tickets a reserver sur ce carnet ;
- la reservation se fait sous verrou FOR UPDATE ;
- le carnet doit appartenir au wallet courant ;
- le carnet doit appartenir a la meme societe que le wallet ;
- le carnet ne doit pas etre expire ;
- qty doit etre positive ;
- qty doit etre inferieure ou egale a qty_available.

## Nouveau contrat API

Endpoint :

POST /api/acpec/fueltoken/v1/mobile/qr/issue

Nouveau payload recommande :

{
  "lines": [
    {"face_line_id": 101, "qty": 4},
    {"face_line_id": 102, "qty": 6}
  ],
  "action_code": "1234",
  "idempotency_key": "..."
}

## Compatibilite temporaire

L'ancien contrat reste accepte pour compatibilite :

{
  "lines": [
    {"carnet_type_id": 12, "qty": 10}
  ],
  "action_code": "1234",
  "idempotency_key": "..."
}

ou :

{
  "lines": [
    {"face_value": 500, "qty": 10}
  ],
  "action_code": "1234",
  "idempotency_key": "..."
}

Cet ancien contrat garde l'allocation automatique FIFO.

## Interdiction des payloads mixtes

Patch34B interdit de melanger dans un meme QR :

- selection explicite par face_line_id ;
- allocation automatique par carnet_type_id ou face_value.

Exemple refuse :

{
  "lines": [
    {"face_line_id": 101, "qty": 2},
    {"carnet_type_id": 12, "qty": 3}
  ]
}

Raison : un QR doit etre explicable. Soit il est constitue de carnets explicitement choisis, soit il utilise l'ancien mode automatique. Les deux modes ne doivent pas etre melanges dans la meme emission.

## Endpoint /mobile/faces

L'endpoint /mobile/faces expose maintenant les identifiants de carnet necessaires au choix explicite :

- id ;
- face_line_id ;
- carnet_no ;
- lot_short_code ;
- carnet_short_code ;
- carnet_sequence ;
- qty_available ;
- qty_qr_active ;
- qty_consumed ;
- expires_at.

Le mobile doit appeler /mobile/faces pour afficher les carnets disponibles, puis transmettre face_line_id dans /mobile/qr/issue.

## Moteur backend

La methode acpec.fuel.face.line.reserve_available(wallet, requests) accepte maintenant deux modes :

1. Mode explicite :
   - face_line_id obligatoire ;
   - reservation sur cette ligne uniquement.

2. Mode legacy :
   - carnet_type_id ou face_value ;
   - allocation automatique FIFO sur les lignes disponibles.

Le mode explicite verrouille la ligne cible avec FOR UPDATE avant de modifier :

- qty_available ;
- qty_qr_active.

## Limites volontaires de Patch34B

Patch34B ne supprime pas encore l'ancien contrat carnet_type_id / face_value.

Patch34B ne refond pas encore :

- split/retrait QR ;
- consommation station ;
- transfert de carnet ;
- UX mobile finale ;
- affichage back-office final ;
- normalisation OTP/register SIGNUP_NOT_ALLOWED vs VALIDATION_ERROR.

Ces sujets restent pour les patches suivants.

## Validation

Validation realisee le 23/06/2026.

Test cible QR issue :

- TestQrIssueRuntimePolicy ;
- 8 post-tests ;
- 0 failed ;
- 0 error.

Test elargi API/core/test :

- 102 post-tests ;
- 0 failed ;
- 0 error.

Perimetre couvert :

- emission QR par face_line_id ;
- rejet d'un carnet appartenant a un autre wallet ;
- rejet d'un payload mixte explicite + automatique ;
- maintien de l'ancien contrat carnet_type_id ;
- maintien de l'idempotence ;
- maintien du controle action_code ;
- maintien du controle trusted device.

## Suite prevue

- Patch34C : transfert de carnet intact par changement direct de wallet_id.
- Patch34D : nettoyage UX mobile/back-office autour des carnets.
- Patch33B ou patch separe : normalisation des erreurs publiques register/OTP.
- Finition securite runtime avant production.

# Contrat mobile carnets - Patch34E

## Contexte

Patch34A a fixé la granularité métier :

1 acpec.fuel.face.line = 1 carnet.

Patch34B a rendu l’émission QR explicite par face_line_id.

Patch34C a corrigé le transfert intact : le même carnet est déplacé vers le wallet destinataire.

Patch34D a nettoyé les libellés visibles : Carnet / Carnets / Carnet source / Carnet destination.

Patch34E ne modifie pas le code métier. Il fige le contrat backend/mobile à utiliser pour l’alignement Flutter.

## Décision importante

La route historique suivante est conservée :

POST /api/acpec/fueltoken/v1/mobile/faces

Malgré son nom historique "faces", cette route est désormais le contrat officiel backend pour lister les carnets disponibles du wallet mobile.

Elle ne doit pas être renommée immédiatement afin d’éviter une rupture API.

Côté Flutter, l’écran métier doit l’afficher comme :

Carnets disponibles

## Route officielle pour Flutter

POST /api/acpec/fueltoken/v1/mobile/faces

Payload minimal :

{}

Payload avec filtre transfert :

{
  "transferable_only": true
}

Réponse :

{
  "items": [
    {
      "id": 123,
      "face_line_id": 123,
      "carnet_no": "ACH-2026-00013-L01-C003",
      "lot_short_code": "P3AVG",
      "carnet_short_code": "P3AVG-C003",
      "carnet_sequence": 3,
      "purchase": "ACH-2026-00013",
      "purchase_id": 45,
      "purchase_line_id": 78,
      "carnet_type": "C10T-500",
      "carnet_type_id": 5,
      "carnet_type_code": "C10T-500",
      "carnet_type_name": "Carnet 10 tickets de 500",
      "face_count": 10,
      "face_value": 500,
      "qty_initial": 10,
      "qty_available": 10,
      "qty_qr_active": 0,
      "qty_qr_blocked": 0,
      "qty_consumed": 0,
      "qty_expired": 0,
      "is_transferable": true,
      "transferable_carnets": 1,
      "expires_at": "2026-12-31 23:59:59"
    }
  ]
}

## Clé à utiliser côté Flutter

La clé technique à utiliser pour QR et transfert est :

face_line_id

Ne pas utiliser carnet_no, carnet_short_code ou lot_short_code comme clé d’action.

Ces champs sont des identifiants métier/audit/affichage.

## Émission QR

Route :

POST /api/acpec/fueltoken/v1/mobile/qr/issue

Payload recommandé :

{
  "lines": [
    {"face_line_id": 123, "qty": 1}
  ],
  "idempotency_key": "..."
}

Règle :

- face_line_id est le contrat recommandé ;
- carnet_type_id et face_value restent acceptés en legacy ;
- il est interdit de mélanger face_line_id avec carnet_type_id / face_value dans le même QR.

## Transfert de carnet

Route :

POST /api/acpec/fueltoken/v1/mobile/carnets/transfer

Payload recommandé :

{
  "recipient_phone": "...",
  "lines": [
    {"face_line_id": 123, "carnet_qty": 1}
  ],
  "action_code": "1234",
  "idempotency_key": "..."
}

Règle :

- face_line_id identifie le carnet source ;
- carnet_qty doit normalement être 1 après Patch34A ;
- le backend vérifie que le carnet est intact et transférable ;
- le transfert déplace le même carnet vers le wallet destinataire ;
- dest_face_line_id est conservé en compatibilité, mais pointe vers le même face_line_id.

## Affichage recommandé Flutter

Liste des carnets :

- titre écran : Carnets disponibles ;
- identifiant visible principal : carnet_short_code ;
- sous-identifiant optionnel : carnet_no ;
- type : carnet_type_name ou carnet_type_code ;
- valeur ticket : face_value ;
- nombre de tickets disponibles : qty_available ;
- expiration : expires_at ;
- statut transfert : is_transferable.

Pour une action QR :

- utiliser face_line_id ;
- demander qty en nombre de tickets/faces à mettre dans le QR.

Pour un transfert :

- utiliser face_line_id ;
- proposer seulement les carnets avec is_transferable = true ;
- envoyer carnet_qty = 1.

## Champs legacy conservés

Les champs suivants restent présents pour compatibilité :

- carnet_type_id ;
- carnet_type_code ;
- face_value ;
- face_count ;
- qty_available.

Ils peuvent être utilisés pour affichage et regroupement, mais ne doivent plus être utilisés comme clé principale d’action mobile.

## Limites volontaires Patch34E

Patch34E ne crée pas de nouvelle route.

Patch34E ne renomme pas /mobile/faces.

Patch34E ne modifie pas le payload.

Patch34E ne supprime pas les chemins legacy.

Patch34E sert à stabiliser le contrat avant l’alignement Flutter.

## Point d’attention

Le nom technique face_line_id est conservé.

Côté métier, il doit être compris comme :

Identifiant technique du carnet.

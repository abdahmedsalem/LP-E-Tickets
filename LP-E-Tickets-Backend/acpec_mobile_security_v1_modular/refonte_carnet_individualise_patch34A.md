# Refonte carnet individualise - Patch34A

## Contexte

Patch34A refond la granularite de acpec.fuel.face.line.

Avant Patch34A, une face_line representait un stock agrege de tickets issu d'une ligne d'achat dans un wallet.

Apres Patch34A, une face_line represente un carnet physique/logique individualise.

## Doctrine retenue

1 face_line = 1 carnet.

Le carnet devient l'unite de base pour la disponibilite, la validite, l'affichage back-office, le futur affichage mobile, le futur choix QR / bon de consommation et le futur transfert de carnet.

wallet_id represente uniquement le detenteur courant du carnet.

Aucun tracking supplementaire des changements de wallet n'est ajoute dans la V1.

## Exemple

Achat de 3 carnets de 10 tickets.

Avant Patch34A :

1 face_line avec qty_initial = 30 et qty_available = 30.

Apres Patch34A :

3 face_line :
- C001 qty_initial = 10 qty_available = 10
- C002 qty_initial = 10 qty_available = 10
- C003 qty_initial = 10 qty_available = 10

## Identite carnet

Champs ajoutes sur acpec.fuel.face.line :

- carnet_no
- lot_short_code
- carnet_short_code
- carnet_sequence

Exemple reel de preuve shell Patch34A :

ACH-2026-00013-L01-C001 P3AVG P3AVG-C001 seq=1 qty_initial=10 qty_available=10
ACH-2026-00013-L01-C002 P3AVG P3AVG-C002 seq=2 qty_initial=10 qty_available=10
ACH-2026-00013-L01-C003 P3AVG P3AVG-C003 seq=3 qty_initial=10 qty_available=10

## Regles techniques

- lot_short_code est commun aux carnets d'une meme ligne d'achat.
- carnet_short_code est unique par societe.
- carnet_no est unique par societe.
- Les codes courts ne dependent pas du wallet.
- La contrainte historique UNIQUE(purchase_line_id, wallet_id) est supprimee car elle empechait plusieurs carnets pour une meme ligne d'achat et un meme wallet.

## Limites volontaires de Patch34A

Patch34A ne refond pas encore :

- allocation QR ;
- transfert de carnets ;
- API mobile /mobile/faces ;
- portail entreprise ;
- distribution societe ;
- securite runtime OTP/SMS.

Ces sujets sont reserves aux patches suivants.

## Validation

Validation realisee le 23/06/2026 :

Test cible Patch34A :
0 failed, 0 error.

Preuve shell :
achat 3 carnets => 3 face_line.
total qty_initial = 30.
total qty_available = 30.
rollback effectue.

Test elargi FuelToken economique :
107 post-tests.
0 failed.
0 error.

Test global complet :
la configuration dev OTP a ete corrigee avec ACPEC_FUELTOKEN_TEST_MODE=1 et otp_dev_mode=True.
Le global complet reste bloque par 2 echecs OTP/register hors perimetre Patch34A :
- expected SIGNUP_NOT_ALLOWED
- actual VALIDATION_ERROR

Ce reliquat est a traiter dans un patch separe de normalisation des erreurs publiques register/OTP.

## Suite prevue

- Patch34B : QR / bon de consommation avec choix explicite des carnets.
- Patch34C : transfert de carnet intact par changement direct de wallet_id.
- Patch34D : affichage mobile/back-office final et nettoyage UX.
- Patch33B ou patch separe : normalisation SIGNUP_NOT_ALLOWED vs VALIDATION_ERROR pour register/OTP.
- Finition securite : runtime production fail-closed et audit OTP/SMS avant toute mise en production.

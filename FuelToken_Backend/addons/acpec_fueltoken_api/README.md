# ACPEC FuelToken API

Module FuelToken conforme à la doctrine actuelle : lot d’achat → lignes de faces agrégées → QR → consommation station.

Licence : OPL-1.
Auteur : ACPEC SARL.
Site : https://acpec.odoorim.com.

## Breaking change audit achat — transaction_type

Le type historique `achat_carnets` est supprimé volontairement du contrat API pendant la phase de développement. Les clients mobiles et back-office ne doivent plus l'utiliser comme filtre ou type métier.

Nouveaux types d'événements achat :

- `purchase_submitted` : demande d'achat soumise ; aucune valeur carburant n'est encore créée, aucun ticket n'est crédité.
- `purchase_approved` : achat approuvé ; les tickets sont réellement créés et le wallet est crédité.

Cette séparation est volontaire : une soumission d'achat n'est pas une création de valeur carburant. Les anciens filtres `achat_carnets` doivent être corrigés côté application mobile au lieu d'être maintenus en compatibilité silencieuse.

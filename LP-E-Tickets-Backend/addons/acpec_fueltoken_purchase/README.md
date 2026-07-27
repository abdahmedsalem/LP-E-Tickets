# ACPEC FuelToken Purchase

Module FuelToken conforme à la doctrine actuelle : lot d’achat → lignes de faces agrégées → QR → consommation station.

## Preuves de paiement

Les preuves de paiement acceptées sont volontairement limitées à :

- PDF ;
- PNG ;
- JPG/JPEG.

La taille maximale par défaut est de 5 Mo et peut être ajustée via le paramètre système :

```text
acpec_fueltoken_purchase.proof_max_bytes
```

Le nom fourni par le client mobile ou portail est traité comme une indication d’affichage seulement. L’extension stockée est dérivée du contenu réel détecté par signature binaire afin d’éviter les rejets injustifiés des captures d’écran mobiles.

Exemple : un contenu JPEG envoyé avec `proof_filename = "capture.png"` sera stocké comme `capture.jpg`.

Licence : OPL-1.
Auteur : ACPEC SARL.
Site : https://acpec.odoorim.com.

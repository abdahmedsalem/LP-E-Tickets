<p align="center">
  <img src="LP-E-Tickets-Frontend/assets/images/lptickets.png" alt="Leader Petroleum E-Tickets" width="520">
</p>

# LP E-Tickets

LP E-Tickets est une solution mobile de gestion de carnets et tickets de carburant pour Leader Petroleum. Elle met en relation les clients, les stations et le système de gestion Odoo.

## Ce que permet la solution

- authentification sécurisée par numéro de téléphone et OTP ;
- demande et achat de carnets ;
- consultation du solde, des tickets et de l’historique des opérations ;
- ajout, affichage et téléchargement des preuves de paiement ;
- génération et partage de QR codes signés ;
- scan en station, validation de consommation et prévention des doublons ;
- transfert de carnets ou de tickets entre utilisateurs autorisés ;
- consultation de la carte et des informations des stations.

L’administration métier (validation des achats, gestion des comptes, carnets, stations et rapports) est réalisée dans Odoo. L’application mobile ne contient pas d’espace d’administration autonome.

## Organisation du dépôt

| Dossier | Rôle |
| --- | --- |
| `LP-E-Tickets-Frontend` | Application Flutter mobile et web |
| `LP-E-Tickets-Backend` | Modules et services Odoo du projet |

## Architecture en bref

L’application Flutter communique avec Odoo au moyen d’API sécurisées. Odoo reste la source de vérité pour les utilisateurs, achats, paiements, carnets, tickets, stations et consommations. Les QR codes sont vérifiés côté serveur avant toute consommation et les opérations sensibles utilisent des contrôles d’idempotence et de concurrence.

## Démarrer le frontend

Prérequis : Flutter/Dart installés et une instance Odoo configurée.

```bash
cd LP-E-Tickets-Frontend
flutter pub get
flutter run
```

Sous Windows, les scripts `run.ps1` et `run.cmd` peuvent être utilisés pour lancer l’application.

## Vérifier le code

```bash
cd LP-E-Tickets-Frontend
flutter analyze
flutter test
```

Les paramètres de connexion à Odoo doivent être fournis par la configuration d’environnement ou les fichiers de configuration prévus par le projet. Les mots de passe, jetons et fichiers `.env` ne doivent jamais être commités ; le fichier `.gitignore` les exclut du dépôt.

## Sécurité et responsabilités

- ne pas partager de secrets dans le code ou les tickets GitHub ;
- utiliser HTTPS entre l’application et Odoo ;
- vérifier les droits côté serveur, même si l’interface masque une action ;
- conserver les journaux et preuves nécessaires à l’audit ;
- tester les achats, validations, scans, transferts et rejouements avant une mise en production.

## État du projet

Le dépôt contient le frontend Flutter et les modules backend Odoo. Avant une mise en production, l’instance Odoo, les variables d’environnement, les certificats HTTPS, les sauvegardes et les tests d’intégration doivent être validés dans l’environnement cible.

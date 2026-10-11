# Dossier Complet de Configuration — Google Play Console
## Application : LP E-Tickets (Leader Petroleum)
**Identifiant Android (Package)** : `com.odoorim.acpec.lp_e_ticket`

---

## 1. Accès à la Console Google Play

1. Rendez-vous sur : **[https://play.google.com/console](https://play.google.com/console)**
2. Connectez-vous avec votre compte développeur Google Play Organisation (ou compte propriétaire).
3. Dans la liste des applications, cliquez sur **LP E-Tickets** (ou sur **Créer une application** si elle n'a pas encore été créée).

> **Paramètres de création initiale (si l'application n'est pas encore créée)** :
> - **Nom de l'application** : `LP E-Tickets`
> - **Langue par défaut** : Français (France) - `fr-FR`
> - **Type** : Application
> - **Gratuit/Payant** : Gratuit
> - Déclarations : Accepter les conditions d'utilisation et les lois sur l'exportation des États-Unis.

---

## 2. Fichier Binaire à Téléverser (Android App Bundle - AAB)

Le bundle prêt pour la production a été généré et se trouve à cet emplacement sur votre machine :

📁 **Chemin du fichier** :
`/Users/chrif/Desktop/LP-E-Tickets/LP-E-Tickets-Frontend/build/app/outputs/bundle/release/app-release.aab`

* **Format** : `.aab` (Android App Bundle signé)
* **Target SDK** : Android 16 / API 36 (pleinement conforme aux exigences Google Play 2026)
* **Architecture** : Multi-architecture (armeabi-v7a, arm64-v8a, x86_64)

Pour le téléverser :
* Menu **Production** (ou **Test interne** / **Test fermé**) ➔ **Créer une version** ➔ Glissez-déposez `app-release.aab`.

---

## 3. Checklist Complète des Tâches Obligatoires (Dashboard)

Sur le tableau de bord, dans la section **« Configurer votre application »**, complétez les étapes ci-dessous :

### Tâche 1 : Règles de confidentialité (Politique de confidentialité)
* **URL de la politique de confidentialité** :
  ```text
  https://lpft.odoorim.com/privacy
  ```
* *(Hébergée avec succès par le module Odoo `acpec_fueltoken_api`).*

---

### Tâche 2 : Accès aux applications (Identifiants de test pour les réviseurs Google)
> **IMPORTANT** : Google rejette systématiquement les applications avec connexion obligatoire si aucun accès fonctionnel n'est fourni.

* Cochez : **Toutes ou certaines fonctionnalités sont protégées par des restrictions d'accès**.
* Cliquez sur **Ajouter des instructions** :
  * **Nom de l'instruction** : `Compte de test Google Play`
  * **Nom d'utilisateur / Numéro de téléphone** : `27919822`
  * **Mot de passe / Code d'accès** : `OTP: 000000 | Code PIN: 1234`
  * **Instructions détaillées pour le réviseur** :
    ```text
    1. Saisissez le numéro de téléphone : 27919822
    2. Cliquez sur Continuer pour recevoir le challenge SMS.
    3. Le serveur de test est configuré pour accepter le code OTP fixe : 000000
    4. Saisissez le code PIN secret : 1234
    5. L'appareil est automatiquement approuvé par notre politique de sécurité sans intervention manuelle supplémentaire.
    ```
  * *(Optionnel — Compte Agent Station)* : Téléphone `32524659`, OTP `000000`, PIN `1234`.

---

### Tâche 3 : Annonces publicitaires
* Cochez : **Non, mon application ne contient pas d'annonces**.

---

### Tâche 4 : Accès pour les enfants et public cible
* **Tranches d'âge ciblées** : Cochez **18 ans et plus**.
* **Attrait involontaire pour les enfants** : Cochez **Non**.

---

### Tâche 5 : Classification du contenu (Questionnaire IARC)
* **Adresse e-mail** : votre adresse de contact développeur.
* **Catégorie** : **Utilitaires, productivité, communication ou autre**.
* Répondez **Non** à l'ensemble des questions (pas de contenu violent, pas de drogues, pas d'achats avec argent réel de type casino, pas de vulgarité).
* **Résultat obtenu** : Classification **PEGI 3 / Tout public**.

---

### Tâche 6 : Applications d'actualités
* Cochez : **Non, mon application n'est pas une application d'actualités**.

---

### Tâche 7 : Applications de suivi COVID-19 ou de recherche de contacts
* Cochez : **Mon application n'est pas une application publique de recherche des contacts ou de suivi du statut COVID-19**.

---

### Tâche 8 : Sécurité des données (Data Safety Section)
Voici les réponses exactes basées sur le code source de l'application :

1. **Collecte et partage** :
   * L'application collecte-t-elle ou partage-t-elle des données utilisateur ? ➔ **Oui**.
   * Toutes les données utilisateur sont-elles chiffrées en transit ? ➔ **Oui** (protocole HTTPS / TLS).
   * Proposez-vous un moyen pour les utilisateurs de demander la suppression de leurs données ? ➔ **Oui** (via l'écran *Paramètres > Supprimer mon compte* et sur la page web).
   * **URL de demande de suppression** :
     ```text
     https://lpft.odoorim.com/privacy/account_deletion
     ```

2. **Types de données déclarées** :
   * **Coordonnées ➔ Numéro de téléphone** :
     * Collecté : Oui. Partagé : Non.
     * Finalité : Fonctionnalité de l'application, Gestion du compte, Prévention des fraudes.
     * Obligatoire pour utiliser l'application.
   * **Photos et vidéos ➔ Photos** (justificatifs de paiement) :
     * Collecté : Oui. Partagé : Non.
     * Finalité : Fonctionnalité de l'application (téléversement optionnel du reçu bancaire lors de l'achat).
     * Facultatif : Oui.
   * **Position géographique ➔ Position approximative & précise** :
     * Collecté : Oui. Partagé : Non.
     * Finalité : Fonctionnalité de l'application (affichage des stations-service Leader Petroleum les plus proches).
     * Facultatif : Oui (l'utilisateur peut refuser la géolocalisation et utiliser l'app normalement).
   * **Appareil ou autres identifiants ➔ ID d'appareil** :
     * Collecté : Oui. Partagé : Non.
     * Finalité : Sécurité du compte, Prévention des fraudes (contrôle de liaison d'appareil de confiance).
     * Obligatoire.

---

### Tâche 9 : Déclaration des fonctionnalités financières (Financial Features)
* **Type de fonctionnalités financières** :
  * Cochez : **L'application fournit des services de bons/tickets prépayés en circuit fermé (Closed-loop prepaid vouchers)**.
  * Précisez que l'application permet de gérer et de consommer des bons de carburant auprès du réseau exclusif de stations-service Leader Petroleum, sans octroi de crédit ni intermédiation bancaire publique.

---

### Tâche 10 : Fiche principale du Google Play Store

#### Titre et Descriptions :
* **Nom de l'application (Max 30 caractères)** :
  ```text
  LP E-Tickets
  ```
* **Description courte (Max 80 caractères)** :
  ```text
  Tickets et bons de carburant numériques pour le réseau Leader Petroleum.
  ```
* **Description complète (Max 4 000 caractères)** :
  ```text
  LP E-Tickets est la solution mobile officielle de Leader Petroleum pour la gestion, l’émission et l’utilisation de bons de carburant numériques en Mauritanie.

  Destinée aux particuliers, professionnels et gestionnaires de flottes, LP E-Tickets modernise et sécurise l’approvisionnement en carburant dans l’ensemble des stations-service Leader Petroleum.

  FONCTIONNALITÉS CLÉS :
  • Portefeuille de carburant en temps réel : Visualisez instantanément votre solde de tickets, vos types de carnets et vos consommations.
  • Émission de QR Codes sécurisés : Générez en quelques secondes des QR codes de retrait avec code de secours chiffré pour vos véhicules ou chauffeurs.
  • Service rapide en station : Présentez simplement votre QR code à l'agent pompiste pour un ravitaillement précis, rapide et sans manipulation d'espèces.
  • Sécurité & Traçabilité : Chaque opération sensible est protégée par votre code PIN personnel et une authentification forte par SMS.
  • Historique complet : Consultez à tout moment le relevé détaillé de vos transactions, retraits et justificatifs d'achat.
  • Réseau de stations : Localisez facilement les stations-service Leader Petroleum participantes.

  Simplifiez la gestion de votre carburant avec LP E-Tickets, en toute transparence et sécurité.
  ```

#### Coordonnées de contact de la fiche :
* **Adresse e-mail** : `contact@acpec.mr` (ou email support ACPEC)
* **Numéro de téléphone** : `+222 45 25 00 00` (à adapter avec votre numéro officiel)
* **Site web** : `https://acpec.mr` ou `https://lpft.odoorim.com`

#### Éléments graphiques requis :
1. **Icône de l'application** : PNG 32 bits, 512 x 512 px, max 1 Mo.
2. **Graphique de fonctionnalité (Feature Graphic)** : JPEG ou PNG 24 bits, 1024 x 500 px.
3. **Captures d'écran pour téléphone** : Au moins 2 captures d'écran (ratio 16:9 ou 9:16, entre 320 px et 3840 px).

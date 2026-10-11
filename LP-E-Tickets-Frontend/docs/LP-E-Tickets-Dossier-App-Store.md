# Dossier Administratif de Soumission — Apple App Store
## Application : LP E-Tickets (Leader Petroleum)

Ce document est un **brouillon à vérifier avant soumission**. Il ne garantit aucune acceptation Apple. Les accès de démonstration, URLs, déclarations de confidentialité et le traitement effectif des suppressions doivent être vérifiés sur la version déployée.

---

## 1. Informations Générales de l'Application

| Champ App Store Connect | Valeur recommandée | Limite Apple |
| :--- | :--- | :--- |
| **Nom de l’application** | `LP E-Tickets` | Max 30 caractères |
| **Sous-titre** | `Carburant & Bons Électroniques` | Max 30 caractères |
| **Catégorie principale** | `Productivité` (Business) | Obligatoire |
| **Catégorie secondaire** | `Utilitaires` (Utilities) | Recommandé |
| **Classement par âge** | À déterminer avec le questionnaire App Store Connect | Obligatoire |
| **Droits de distribution** | Disponible dans les pays ciblés (Mauritanie, etc.) | Sélection pays |

---

## 2. URLs Légales et d'Assistance (Obligatoires)

La politique ci-dessous est accessible. Les coordonnées d’assistance et la page support doivent encore être confirmées par ACPEC avant saisie :

- **URL de la politique de confidentialité (Privacy Policy URL)** :  
  `https://lpft.odoorim.com/privacy`
- **URL de l’assistance technique (Support URL)** : `https://lpft.odoorim.com`
- **Email de contact support** : `support@acpec.mr`
- **Numéro de téléphone support** : `+222 27919822`
- **Contact responsable** : Ahmed Salem Abdefattah
- **Copyright** : `2026 ACPEC Sarl`

---

## 3. Métadonnées de Version (Texte pour la fiche App Store)

### Description (Français)
```text
LP E-Tickets est la solution officielle de gestion et d’utilisation de bons de carburant numériques développée pour Leader Petroleum.

Conçue pour les entreprises, les gestionnaires de flotte et les particuliers, LP E-Tickets simplifie et sécurise l'approvisionnement en carburant dans l’ensemble du réseau de stations-service Leader Petroleum.

Fonctionnalités principales :
• Portefeuille de tickets carburant : Consultez votre solde de tickets et carnets en temps réel.
• Génération de QR Codes sécurisés : Émettez instantanément des QR codes de retrait avec code numérique associé pour vos chauffeurs ou pour vous-même.
• Validation en station-service : Présentez votre QR code à la pompe pour un service rapide, précis et sans manipulation d’espèces.
• Historique et traçabilité : Suivez en direct vos transactions, vos volumes consommés et vos pièces justificatives.
• Sécurité renforcée : Protection de vos opérations sensibles par code PIN personnel et authentification forte.

LP E-Tickets optimise votre consommation de carburant en toute transparence et simplicité.
```

### Mots-clés (Keywords - Max 100 caractères)
```text
carburant,tickets,essence,gasoil,leader petroleum,station,qr code,bons,mauritanie,flotte
```

### Texte promotionnel (Facultatif - Max 170 caractères)
```text
Gérez et utilisez vos tickets de carburant Leader Petroleum en toute simplicité et sécurité grâce aux QR codes numériques.
```

---

## 4. Informations pour l’Équipe de Validation Apple (App Review Information)

> [!IMPORTANT]
> Les informations d’accès et de test doivent être valides et vérifiées sur la version de production.

### Connexion requise (Sign-in Required) : **OUI**

Utiliser un **compte de démonstration dédié à App Review**, créé et maintenu par ACPEC. Ne pas réutiliser un compte client réel ni enregistrer ici de numéro, OTP, mot de passe ou PIN. Vérifier avant soumission que le compte est actif, que l’équipe Apple peut recevoir ou contourner l’OTP selon une procédure prise en charge par le service, et que les opérations visibles utilisent uniquement des données fictives.

### Notes pour la revue (Review Notes)
Copiez-collez ce texte (en anglais et français) dans le champ **"Review Notes"** d'App Store Connect :

```text
--- INSTRUCTIONS FOR APPLE APP REVIEW TEAM ---

1. DEMO ACCESS:
- Use the dedicated review account credentials entered in the App Review Information fields in App Store Connect.
- OTP/PIN steps: [ACPEC must provide a secure, working review procedure here; do not claim a fixed OTP unless it is implemented and verified on the production service.]

2. APP PURPOSE & FUNCTIONALITY:
LP E-Tickets is an enterprise fuel voucher management app for Leader Petroleum customers in Mauritania. It allows customers to access their pre-purchased electronic fuel tickets, generate QR codes, and redeem them at Leader Petroleum gas stations.

3. ACCOUNT DELETION:
- Describe the in-app deletion request and its actual processing only after ACPEC has verified the production workflow and retention obligations. Do not claim a completion deadline or retained records unless that has been confirmed.

### Coordonnées du contact pour l’examen (App Review Contact Information) :
- **Prénom** : Ahmed Salem
- **Nom** : Abdefattah
- **E-mail** : `support@acpec.mr`
- **Numéro de téléphone** : `+222 27919822`

If you have any questions, please contact the support contact entered in App Store Connect: Ahmed Salem Abdefattah (`support@acpec.mr` / `+222 27919822`).
```

---

## 5. Questionnaire de Confidentialité (App Privacy / Nutrition Labels)

La déclaration ci-dessous reste un brouillon d’audit, pas une réponse prête à publier. Le questionnaire App Store Connect doit être complété après confirmation des pratiques réelles côté serveur Odoo et des prestataires :

### Collectez-vous des données depuis cette app ? **OUI**

#### A. Données de contact (Contact Info)
- **Numéro de téléphone** :
  - *Finalité* : Fonctionnalité de l'application (authentification sécurisée OTP) et Gestion du compte.
  - *Lié à l'utilisateur ?* : **OUI**
  - *Utilisé à des fins de suivi (Tracking) ?* : **NON**

#### B. Données financières (Financial Info)
- **Historique des paiements / transactions de carburant** :
  - *Finalité* : Fonctionnalité de l'application (consultation des soldes et suivi des consommations en station).
  - *Lié à l'utilisateur ?* : **OUI**
  - *Utilisé à des fins de suivi (Tracking) ?* : **NON**

#### C. Localisation (Location)
- **Position approximative ou précise (lors du scan en station)** :
  - *Finalité* : Fonctionnalité de l'application (sécurité et confirmation de présence physique à la station-service).
  - *Lié à l'utilisateur ?* : **NON**
  - *Utilisé à des fins de suivi (Tracking) ?* : **NON**

#### D. Diagnostics
- **Données d'incident / performance** :
  - *Finalité* : Analyse et diagnostic des anomalies techniques.
  - *Lié à l'utilisateur ?* : **NON**
  - *Utilisé à des fins de suivi (Tracking) ?* : **NON**

> [!NOTE]
> **Suivi publicitaire (Tracking)** : Répondez **NON** à la question "Utilisez-vous des données pour suivre les utilisateurs à travers des apps et sites appartenant à d'autres sociétés ?". L'application n'utilise aucune régie publicitaire (pas d'IDFA).

---

## 6. Vérifications Techniques Réalisées dans le Code iOS

- [x] **Clé d'exemption de chiffrement** : `ITSAppUsesNonExemptEncryption = false` ajoutée dans `ios/Runner/Info.plist`. Vous n'aurez plus à répondre aux questions de conformité d'exportation cryptographique lors des téléversements de build.
- [x] **Descriptions des autorisations claires et justifiées** :
  - Caméra : `Leader Petroleum E-Tickets utilise la caméra pour scanner les codes QR à la station.`
  - Géolocalisation : `Leader Petroleum E-Tickets utilise la géolocalisation pour vérifier la présence à la station lors du service de carburant.`
  - Face ID : `Leader Petroleum E-Tickets utilise Face ID pour sécuriser votre connexion.`
  - Photos : `Leader Petroleum E-Tickets enregistre les reçus et preuves de paiement dans votre galerie de photos.`
- [ ] **Parcours de suppression de compte** : traitement manuel sous 7 jours, délai opérationnel choisi par ACPEC. Vérifier en production l’effacement effectif, la justification des données conservées et la confirmation finale au client.

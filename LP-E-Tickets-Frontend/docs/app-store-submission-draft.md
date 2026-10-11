# LP E-Tickets — préparation App Store

État observé le 11 octobre 2026. App Store Connect affiche les builds iOS **7** et **6** (version 1.0.0, « Prêt à soumettre »). Le **build 7** est associé et enregistré sur la version iOS 1.0. La fiche reste « À finaliser avant soumission »; aucun envoi en examen n’a été effectué.

La description française, les mots-clés, le sous-titre « Tickets carburant et QR » et les URLs de confidentialité et d’assistance ont été enregistrés comme brouillon dans App Store Connect. L’URL d’assistance mène à la page de suppression de compte, qui affiche le contact public `support@acpec.mr`. Ces éléments ne sont pas encore publiés.

**Catégorie enregistrée dans App Store Connect :** Utilitaires en catégorie principale et Shopping en catégorie secondaire. La classification par âge 4+ a également été enregistrée après avoir déclaré l’absence des fonctionnalités et contenus concernés par le questionnaire.

## Brouillon de métadonnées

Ces textes sont proposés à partir des fonctionnalités visibles dans l’application et restent à valider par ACPEC.

### Français

- **Nom :** LP E-Tickets
- **Sous-titre enregistré :** Tickets carburant et QR
- **Description proposée :**

  LP E-Tickets vous permet de gérer vos tickets carburant numériques liés à votre compte Leader Petroleum.

  • Consultez vos carnets et tickets disponibles.  
  • Créez des codes QR à partir de vos tickets.  
  • Présentez un QR dans une station autorisée pour faire vérifier et enregistrer une consommation.  
  • Transférez un carnet ou des tickets à un autre bénéficiaire.  
  • Consultez l’état de vos QR et l’historique de vos opérations.

  La connexion se fait avec un numéro de téléphone. La validation des commandes, les moyens de paiement et la disponibilité des opérations dépendent de la configuration du service Leader Petroleum. Une connexion Internet est nécessaire.

- **Mots-clés enregistrés :** carburant,ticket,QR,essence,carnet,station,transfert
- **Texte promotionnel :** à laisser vide pour cette première version, sauf campagne validée par ACPEC.

### العربية

- **العنوان:** LP E-Tickets
- **عنوان فرعي مقترح:** تذاكر الوقود ورموز QR
- **وصف مقترح:**

  يتيح لك تطبيق LP E-Tickets إدارة تذاكر الوقود الرقمية المرتبطة بحسابك لدى Leader Petroleum.

  • اطّلع على دفاتر التذاكر والتذاكر المتاحة لك.  
  • أنشئ رموز QR باستخدام تذاكرك.  
  • قدّم رمز QR في محطة معتمدة للتحقق من عملية الاستهلاك وتسجيلها.  
  • حوّل دفتر تذاكر أو تذاكر إلى مستفيد آخر.  
  • تابع حالة رموز QR وراجع سجل عملياتك.

  يتم تسجيل الدخول باستخدام رقم الهاتف. ويعتمد اعتماد الطلبات ووسائل الدفع وتوفر العمليات على إعدادات خدمة Leader Petroleum. يلزم الاتصال بالإنترنت.

## Informations à fournir par ACPEC

- URL de politique de confidentialité : `https://lpft.odoorim.com/privacy` (page ouverte le 11 octobre 2026).
- URL marketing facultative : à confirmer; la page racine du VPS ouvre la connexion Odoo et ne sert pas de page marketing.
- Compte de démonstration dédié à l’équipe Apple, avec données fictives. Ne pas enregistrer de vrai numéro, OTP, PIN ou mot de passe dans ce document. Valider sur le serveur de production la procédure d’accès de l’équipe Apple.
- Coordonnées de la personne de contact pour la vérification.
- Confirmation de la catégorie App Store et de la disponibilité géographique.
- Confirmation des données réellement collectées par le serveur Odoo, de leur usage, des destinataires et de leur durée de conservation. Le fichier `ios/Runner/PrivacyInfo.xcprivacy` déclare l’absence de suivi et aucune donnée collectée dans le manifeste de confidentialité iOS, mais ce fichier ne remplace pas les réponses « Confidentialité de l’app » dans App Store Connect.

## Confidentialité et autorisations à vérifier

Le `Info.plist` déclare des accès à la caméra (scan QR), à Face ID, à la localisation et à la photothèque (preuve de paiement). Avant de répondre aux questions App Store Connect :

- confirmer si l’application collecte réellement la localisation et si elle en a besoin en arrière-plan ; le texte `NSLocationAlwaysAndWhenInUseUsageDescription` devra être justifié par un usage réel ;
- confirmer si une preuve photo est téléversée vers Odoo, conservée localement ou les deux, et pendant combien de temps ;
- inventorier côté serveur le numéro de téléphone, les données de compte, commandes, paiements, carnets, QR, transferts et consommations ;
- ne pas déclarer « aucune donnée collectée » sur la seule base du manifeste iOS.

## Captures d’écran à produire

Prendre des captures réelles de la version iPhone avec des données de démonstration uniquement :

1. Accueil / portefeuille avec données de démonstration.
2. Liste des carnets et détail d’un carnet.
3. Liste et détail d’un QR actif.
4. Parcours de génération d’un QR.
5. Parcours de transfert d’un carnet ou de tickets.
6. Historique des opérations.

Vérifier que les captures correspondent à l’interface et à la langue déclarées sur la fiche. Les données présentes dans la série actuelle ont été confirmées comme données de démonstration par ACPEC.

Une série de neuf captures iPhone 16e issues du simulateur a été copiée sans retouche dans `docs/app-store/screenshots/`. Le 11 octobre 2026, les neuf fichiers ont été importés dans la Bibliothèque de ressources d’App Store Connect. Apple les affiche comme captures compatibles avec un iPhone Face ID à écran moyen; leur état propose encore « Ajouter pour vérification ». Elles ne sont donc pas encore placées/validées sur la page produit de la version iOS 1.0.

## Avant « Ajouter pour vérification »

- [x] Vérifier le build téléversé et associer le build 7 à la version iOS 1.0.
- Compléter les métadonnées et placer les captures importées dans la série iPhone de la page produit; soumettre les ressources à vérification quand ACPEC aura validé leur ordre et leur contenu.
- Fournir et valider les droits relatifs au contenu (le titulaire doit confirmer les droits d’usage de la marque et des images).
- [x] Remplir le questionnaire de classification par âge (résultat enregistré : 4+).
- Remplir le questionnaire de confidentialité à partir des pratiques réelles du service et des données traitées côté Odoo.
- Ajouter les notes et accès de test nécessaires à Apple.
- Exécuter un test de bout en bout du compte de démonstration : connexion, carnet, création de QR, transfert et consultation d’historique. Les paiements réels ne doivent pas être déclenchés pendant l’examen.
- Vérifier les obligations de conformité affichées par App Store Connect pour l’équipe (dont le statut de commerçant UE si la distribution dans l’UE est souhaitée).
- Soumettre ensuite à l’examen. Ne pas cliquer sur « Ajouter pour vérification » avant que les informations et le compte de test soient validés par ACPEC.

# AGENTS.md — FuelToken Flutter

Instructions pour l’IA qui développe l’application Flutter **Tickets Carburant / FuelToken**.
À respecter sur chaque tâche, sans exception.

---

## 0. État de référence

Le contrat API mobile est une **référence backend réelle**, pas une spec souhaitée.
Ne jamais inventer un endpoint, un champ, un code d’erreur ou un payload qui n’est pas documenté dans le contrat API de référence.

Objectif immédiat après stabilisation backend H5H :

```text
Flutter/API public error contract alignment
```

Le backend est considéré stable côté V1 sécurité mobile jusqu’au tag :

```text
security-runtime-v1-20260628-patch43H5H
```

Décision H5H :

```text
Aucun patch runtime backend requis avant Flutter.
Les corrections à faire maintenant sont côté Flutter/API contract.
```

---

## 1. Environnement local Flutter

### Repo Flutter

```powershell
cd D:\dev\github\fuelToken\Fueltoken_Frontend
```

### Préparation Flutter

```powershell
flutter clean
flutter pub get
```

### Backend local Odoo

Le backend Odoo local est exposé sur le PC via le port :

```text
8019
```

Pour un appareil Android physique, utiliser `adb reverse` afin que l’app sur le téléphone accède au backend local via `localhost:8019` / `127.0.0.1:8019`.

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

& $adb reverse tcp:8019 tcp:8019
& $adb reverse --list
```

### Lancement sur appareil de test

Appareil connu :

```text
R5CY213Z12F
```

Commande :

```powershell
flutter run -d R5CY213Z12F
```

### Base URL attendue côté app

Pour l’app exécutée sur l’appareil Android avec `adb reverse` :

```text
http://127.0.0.1:8019
```

ou équivalent local selon la configuration Flutter existante.

Ne pas remplacer par l’IP LAN tant que le flux `adb reverse` est utilisé.

---

## 2. Discipline de travail

### Avant toute modification

1. Lire ce `AGENTS.md`.
2. Lire le contrat API mobile de référence.
3. Inspecter le code Flutter actuel.
4. Faire une extraction factuelle des fichiers touchés.
5. Proposer le périmètre du patch.
6. Attendre validation si le patch change une doctrine, un flow ou une architecture.
7. Patch chirurgical uniquement.
8. Lancer les vérifications Flutter.
9. Commit propre, puis merge/tag/push si demandé.

### Interdits

```text
- Ne pas inventer de champ backend.
- Ne pas dépendre des messages exacts backend.
- Ne pas exposer debug_reason en production.
- Ne pas afficher d’erreur technique brute.
- Ne pas créer deux composants visuels pour le même usage.
- Ne pas ajouter de dépendance Flutter sans justification.
- Ne pas refactorer massivement pendant un patch de contrat API.
- Ne pas mélanger Flutter, backend et documentation canonique dans un même patch.
```

---

## 3. Principes UI

- **Uniforme** : réutiliser un composant/style existant avant d’en créer un.
- **Sobre** : pas d’ornement, pas d’emoji UI, pas de couleur ou taille hors thème.
- **Professionnel** : cohérent d’un écran à l’autre, finitions soignées.
- **Intuitif** : un écran = une intention claire.
- **Rien d’inutile** : pas de code mort, pas de widget “au cas où”, pas de dépendance non justifiée.

---

## 4. Règles concrètes Flutter

- Couleurs, espacements, typographie : toujours via le thème.
- Aucun écran ne doit contenir de couleur, taille ou espacement arbitraire en dur.
- Boutons, champs, cartes, dialogs, loaders, états vides : composants partagés.
- Chaque écran gère 4 états : chargement, vide, erreur, succès.
- Aucun écran sans gestion d’erreur.
- Textes centralisés, UI en français.
- Navigation et app-bar cohérentes entre rôles.
- Les repositories/services API ne doivent pas contenir de logique UI.
- Les widgets ne doivent pas parser directement le JSON backend.
- Tout mapping backend → modèle Dart doit passer par une couche dédiée.

---

## 5. Contrat transport API

Toutes les routes backend sont appelées en JSON-RPC 2.0.

### Requête

Toujours envoyer le corps métier dans `params` :

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "id": 1,
  "params": {}
}
```

### Réponse

La réponse applicative est dans `result`.

Succès :

```json
{
  "ok": true,
  "success": true,
  "data": {}
}
```

Erreur :

```json
{
  "ok": false,
  "success": false,
  "error": {
    "code": "RATE_LIMITED",
    "message": "Trop de tentatives. Réessayez plus tard.",
    "reference": "SEC-..."
  }
}
```

Règle Flutter :

```text
Toujours lire result.ok ou result.success.
En cas d’erreur, brancher la logique sur result.error.code.
Ne jamais brancher la logique sur result.error.message.
```

---

## 6. Contrat erreurs publiques

### À faire

- Centraliser le mapping `error.code` → message UX localisé.
- Afficher la `reference` si elle est présente et utile au support.
- Accepter les références `SEC-*` et `ERR-*`.
- Prévoir un fallback UX pour code inconnu.

### À ne pas faire

```text
- Ne pas matcher les messages backend exacts.
- Ne pas afficher debug_reason.
- Ne pas afficher traceback / exception / payload technique.
- Ne pas traiter HTTP 200 comme succès métier.
- Ne pas traiter JSON-RPC success comme succès métier si result.ok=false.
```

Codes sensibles à gérer au minimum :

```text
AUTH_REFUSED
RATE_LIMITED
DEVICE_NOT_ALLOWED
ACTION_REFUSED
QR_NOT_USABLE
TRANSFER_REFUSED
REQUEST_REFUSED
FORBIDDEN
SIGNUP_NOT_ALLOWED
VALIDATION_ERROR
ACCESS_ERROR
AUTH_REQUIRED
REFRESH_TOKEN_REQUIRED
SERVER_ERROR
PASSWORD_LOGIN_DISABLED
NAME_REQUIRED
SECRET_CODE_REQUIRED
SECRET_CODE_INVALID
PHONE_REQUIRED
```

---

## 7. Authentification et device

### Principes

- Pas de login mot de passe.
- Flux unique : OTP → tokens Bearer.
- Tokens opaques : ne rien lire dedans.
- Stockage sécurisé obligatoire.
- `device_uid` stable obligatoire.
- Un nouveau device est `pending_trust` jusqu’à approbation.
- Pas de TOFU côté Flutter.
- `pending_trust` autorise auth/profil mais bloque le métier.

### `device_uid`

Le `device_uid` doit être :

```text
stable
persistant
propre à l’appareil
stocké en sécurité
jamais régénéré à chaque lancement
jamais un placeholder bloqué
```

Placeholders interdits côté backend :

```text
flutter-android-local
flutter-ios-local
flutter-web-local
web-local
```

### UI selon `device_trust_state`

```text
pending_trust -> écran attente validation appareil
trusted       -> application métier complète
blocked       -> écran blocage / déconnexion contrôlée
```

---

## 8. Identité et validation locale

Le backend ne normalise pas.

Flutter doit valider/nettoyer avant envoi :

```text
Téléphone : ^[234][0-9]{7}$
PIN       : ^[0-9]{4}$
```

Ne pas envoyer :

```text
+222
espaces
tirets
PIN non numérique
PIN autre que 4 chiffres
```

---

## 9. Actions sensibles

Toute mutation de valeur exige :

```text
device trusted
action_code
idempotency_key
```

### `action_code`

- C’est le PIN mobile à 4 chiffres.
- Envoyer uniquement sous la clé `action_code`.
- Ne jamais envoyer `action_pin`, `pin` ou `secret_code` pour une action sensible.

### `idempotency_key`

- UUID v4 généré une fois par intention utilisateur.
- Réutilisé sur retry réseau de la même intention.
- Ne pas régénérer à chaque tap.
- Ne pas réutiliser pour une intention différente.

---

## 10. `request-otp` et shape oracle

OPEN connu :

```text
OPEN-H5C-FLUTTER-001
```

Le backend peut répondre avec ou sans `challenge_id` selon le contexte connu/inconnu.

Règles Flutter :

```text
- gérer les deux formes ;
- ne pas supposer que challenge_id est toujours présent ;
- ne pas afficher de message qui énumère un compte ;
- baser la logique sur ok/success/code/purpose/présence de challenge_id ;
- garder un flux UX générique lorsque le backend masque l’existence du compte.
```

---

## 11. Rôles et endpoints

Ne pas exposer dans l’app les endpoints manager explicitement back-office-only.

Côté navigation :

```text
client/base user -> wallet, faces, QR, purchases, transfers
station          -> station profile, qr check, qr use, station transactions
manager          -> validations positives autorisées seulement
```

Le manager mobile est un valideur positif, pas un administrateur de configuration.

---

## 12. Icône réglages

- Référence à reprendre de l’écran user : uniquement le placement de l’icône.
- Station et admin placent l’icône réglages au même endroit.
- Le contenu et le comportement du menu restent propres à chaque rôle.
- Ne pas copier le menu user vers station/admin.

---

## 13. Avant de livrer

Vérifications minimales :

```powershell
flutter analyze
flutter test
```

Checklist :

```text
[ ] flutter analyze au vert
[ ] flutter test au vert
[ ] aucun doublon visuel
[ ] composants et thème existants réutilisés
[ ] aucune couleur / taille / espacement arbitraire en dur
[ ] aucun texte dispersé hors mécanisme de centralisation existant
[ ] les 4 états sont gérés sur tout nouvel écran
[ ] erreurs API basées sur error.code, pas message
[ ] reference SEC-* / ERR-* gérée proprement
[ ] debug_reason jamais affiché
[ ] device pending_trust / trusted / blocked géré
[ ] action_code et idempotency_key conformes
[ ] request-otp avec/sans challenge_id géré
```

---

## 14. Commandes utiles

### Préparation complète

```powershell
cd D:\dev\github\fuelToken\Fueltoken_Frontend

flutter clean
flutter pub get

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb reverse tcp:8019 tcp:8019
& $adb reverse --list

flutter run -d R5CY213Z12F
```

### Contrôle Git

```powershell
git status -sb
git diff --stat
git diff --check
```

---

## 15. But du prochain patch Flutter

Premier patch recommandé :

```text
Flutter/API public error contract alignment
```

Périmètre :

```text
- transport JSON-RPC robuste ;
- mapping centralisé error.code ;
- affichage propre reference ;
- suppression de toute dépendance aux messages backend exacts ;
- gestion request-otp avec/sans challenge_id ;
- aucun changement backend.
```

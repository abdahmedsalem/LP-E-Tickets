# Passation — FuelToken Flutter / API public error contract

Date : 2026-06-28
But : préparer un nouveau chat ou un nouvel agent IA à reprendre le chantier Flutter après stabilisation backend H5H.

---

## 1. État backend de référence

Backend stabilisé côté sécurité mobile jusqu’à :

```text
security-runtime-v1-20260628-patch43H5H
```

Décisions récentes importantes :

```text
H5G   doctrine sources settings sécurité mobile
H5G2  doc_refonte confirmé comme documentation canonique
H5H   revue doctrine/code/tests backend : aucun patch runtime requis avant Flutter
```

Décision H5H :

```text
Le backend ne bloque plus le passage à Flutter.
Les points ouverts SMS/ICP, public_auth_min_latency_ms et web-session guard sont non bloquants V1.
```

---

## 2. Documentation de référence

Documentation canonique backend/doctrine :

```text
D:\dev\github\fuelToken\doc_refonte
```

Repo backend :

```text
D:\dev\github\fuelToken\FuelToken_Backend
```

Repo Flutter :

```text
D:\dev\github\fuelToken\Fueltoken_Frontend
```

Contrat Flutter/API à respecter :

```text
FuelToken — Contrat API mobile (référence Flutter)
```

Ce contrat reflète le backend réel. Si un champ n’est pas listé, ne pas l’inventer.

---

## 3. Environnement Flutter local

### Préparation

```powershell
cd D:\dev\github\fuelToken\Fueltoken_Frontend

flutter clean
flutter pub get
```

### ADB reverse vers backend Odoo local

Backend local attendu sur le port PC :

```text
8019
```

Commande :

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

& $adb reverse tcp:8019 tcp:8019
& $adb reverse --list
```

### Appareil Android de test

```text
R5CY213Z12F
```

Commande :

```powershell
flutter run -d R5CY213Z12F
```

Base URL côté app avec `adb reverse` :

```text
http://127.0.0.1:8019
```

ou valeur équivalente déjà configurée dans le projet.

---

## 4. Discipline de travail

Ne pas patcher directement.

Toujours faire :

```text
1. extraction du code Flutter actuel ;
2. cartographie des services API / repositories / modèles / écrans ;
3. constat factuel ;
4. proposition de patch ;
5. validation du périmètre ;
6. patch chirurgical ;
7. flutter analyze ;
8. flutter test ;
9. git diff --check ;
10. commit propre.
```

Ne pas mélanger :

```text
backend
Flutter
documentation canonique
refactor massif
```

---

## 5. Contrat API à respecter côté Flutter

### JSON-RPC

Toutes les requêtes doivent être enveloppées :

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "id": 1,
  "params": {}
}
```

Lire la réponse dans :

```text
result
```

Succès métier :

```text
result.ok == true
```

Erreur métier :

```text
result.ok == false
result.error.code
```

Règle absolue :

```text
Ne jamais brancher la logique Flutter sur result.error.message.
Toujours utiliser result.error.code.
```

### Références support

Gérer et afficher proprement si présent :

```text
SEC-*
ERR-*
```

Ne jamais afficher :

```text
debug_reason
traceback
exception technique
```

---

## 6. Auth et device

### Device UID

Le `device_uid` doit être stable, persistant et stocké côté appareil.

Interdits :

```text
flutter-android-local
flutter-ios-local
flutter-web-local
web-local
```

### Device trust

```text
pending_trust -> écran attente validation
trusted       -> app métier ouverte
blocked       -> blocage / déconnexion
```

Un nouveau device n’est pas auto-trusted.

### Tokens

- `access_token` Bearer.
- `refresh_token`.
- Stockage sécurisé.
- Refresh automatique si access expiré.
- Logout si refresh expiré.

---

## 7. Signup / OTP

### Téléphone

```text
^[234][0-9]{7}$
```

Pas de `+222`, pas d’espaces, pas de tirets.

### PIN

```text
^[0-9]{4}$
```

### request-otp

Point ouvert connu :

```text
OPEN-H5C-FLUTTER-001
```

La réponse peut contenir ou non `challenge_id`.

Flutter doit gérer les deux formes sans énumérer les comptes.

---

## 8. Actions sensibles

Toute mutation exige :

```text
action_code
idempotency_key
device trusted
```

`action_code` :

```text
PIN mobile 4 chiffres
clé unique autorisée : action_code
```

`idempotency_key` :

```text
UUID v4 par intention utilisateur
réutilisée sur retry réseau
jamais régénérée à chaque tap
```

---

## 9. Premier patch recommandé

Nom proposé :

```text
patch-flutter-public-error-contract-alignment
```

Objectif :

```text
Corriger Flutter pour consommer correctement le contrat public backend :
- JSON-RPC result.ok ;
- error.code ;
- reference SEC-* / ERR-* ;
- request-otp avec/sans challenge_id ;
- device_trust_state ;
- messages UX localisés côté app.
```

Hors périmètre :

```text
- aucun backend ;
- aucun changement H5G/H5H ;
- aucun refactor UI massif ;
- aucune nouvelle fonctionnalité métier ;
- aucune correction SMS/ICP.
```

---

## 10. Extraction Flutter à faire en premier

Depuis Git Bash ou PowerShell :

```powershell
cd D:\dev\github\fuelToken\Fueltoken_Frontend

git status -sb
git branch --show-current
git log --oneline --decorate -10
```

Rechercher :

```powershell
Select-String -Path .\lib\**\*.dart `
  -Pattern "jsonrpc|result.ok|success|error.code|message|reference|SEC-|ERR-|RATE_LIMITED|challenge_id|device_uid|device_trust_state|action_code|idempotency_key" `
  -CaseSensitive:$false
```

À classer :

```text
1. couche transport HTTP / JSON-RPC
2. services API auth / OTP / signup
3. models Dart de réponse
4. repositories métier
5. mapping erreurs
6. écrans qui affichent les erreurs
7. stockage tokens/device_uid
8. actions sensibles
```

---

## 11. Checklist avant livraison Flutter

```text
[ ] flutter analyze
[ ] flutter test
[ ] git diff --check
[ ] aucune logique basée sur message exact
[ ] mapping error.code centralisé
[ ] reference affichée proprement si présente
[ ] debug_reason jamais affiché
[ ] request-otp avec/sans challenge_id géré
[ ] device pending_trust/trusted/blocked géré
[ ] idempotency_key par intention utilisateur
[ ] action_code uniquement pour mutations sensibles
[ ] aucun endpoint back-office-only exposé dans l’app
```

---

## 12. Avocat du diable

Les risques Flutter les plus probables ne sont plus côté backend :

```text
- UI qui matche des messages exacts ;
- transport qui prend HTTP 200 pour succès métier ;
- parsing qui ignore result.ok ;
- request-otp supposant toujours challenge_id ;
- device_uid régénéré trop souvent ;
- pending_trust mal routé ;
- idempotency_key régénérée sur retry ;
- debug_reason ou détails techniques affichés en prod.
```

La priorité est donc de verrouiller la couche Flutter de contrat API avant tout écran métier supplémentaire.

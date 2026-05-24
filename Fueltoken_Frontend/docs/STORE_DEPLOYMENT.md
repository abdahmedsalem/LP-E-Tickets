# FuelToken — déploiement App Store & Google Play

Guide pour une structure **production-ready**, conforme aux règles iOS (ATS) et Android (réseau / signature), et alignée sur l’architecture du dépôt.

Voir aussi : [`PRODUCTION_STEPS.md`](PRODUCTION_STEPS.md) (builds rapides), [`ODOO_JSONRPC_INTEGRATION.md`](ODOO_JSONRPC_INTEGRATION.md).

---

## 1. Architecture applicative (niveau production)

```
lib/
├── core/           # Config compile-time, auth, router, thème, bootstrap store
├── data/           # Modèles, repositories, services Odoo/ACPEC, mappers
├── features/       # UI par domaine (auth, home, wallet, qr, admin, station, …)
└── shared/         # Widgets réutilisables (cartes, Lottie, badges)
```

| Couche | Rôle |
|--------|------|
| `core/config/*` | `ODOO_JSONRPC_BASE_URL`, flags `ODOO_USE_ACPEC_AUTH`, politique HTTPS release |
| `core/bootstrap/` | Écran bloquant si release sans API ou en HTTP |
| `data/services/odoo_fueltoken_facade.dart` | Point d’entrée métier Odoo |
| `features/*/bloc` | État UI (ex. `AuthBloc`, `WalletCubit`) |
| `go_router` | `core/router/app_router.dart` — navigation par rôle |

**Règles métier stores déjà dans le code**

- Release sans `ODOO_JSONRPC_BASE_URL` → écran *Configuration API requise* (sauf `ALLOW_OFFLINE_DEMO=true`).
- Release avec URL `http://` → écran *HTTPS requis* + échec de `./scripts/run.sh build … --release`.
- Android release : pas de cleartext ; debug seulement : HTTP autorisé.
- iOS : `NSAllowsArbitraryLoads=false`, `NSAllowsLocalNetworking=true` (réseau local en dev).

---

## 2. Prérequis serveur

- [ ] Odoo ACPEC accessible en **HTTPS** avec certificat valide (Let’s Encrypt ou CA reconnue).
- [ ] Même origine que `ODOO_JSONRPC_BASE_URL` (sans chemin `/api/...` dans la base — voir `OdooApiConfig`).
- [ ] CORS / pare-feu : autoriser l’app mobile (pas de blocage des POST JSON-RPC).
- [ ] (Optionnel) Service REST OTP : `API_BASE_URL=https://…` si inscription OTP externe.

---

## 3. Configuration locale & CI

```bash
cp scripts/env/flutter.mobile.example.env scripts/env/flutter.mobile.env
# Éditer : ODOO_JSONRPC_BASE_URL=https://production.example
```

Variables minimales release :

```bash
ODOO_JSONRPC_BASE_URL=https://votre-odoo.example
ODOO_USE_ACPEC_AUTH=true
ODOO_FUEL_ENABLED=true
```

**Ne pas** committer `scripts/env/flutter.mobile.local.env` (surcharges perso), `android/key.properties`, `*.jks`.  
`flutter.mobile.env` est versionné pour l’équipe dev ; utilisez **HTTPS** pour les builds store.

---

## 4. Qualité avant soumission

```bash
flutter pub get
dart analyze
flutter test
./scripts/run.sh build appbundle --release   # Android
./scripts/run.sh build ipa --release         # iOS (macOS + Xcode)
```

Checklist manuelle :

- [ ] Connexion Client / Admin / Station sur build **release** pointant prod.
- [ ] Scan QR, biométrie, pièce jointe achat carnets (permissions iOS déjà dans `Info.plist`).
- [ ] Pas de bannière debug, pas de comptes seed (`ALLOW_OFFLINE_DEMO` absent).
- [ ] Version : `pubspec.yaml` → `version: x.y.z+build` (incrémenter `+build` à chaque upload store).

---

## 5. Android (Google Play)

### 5.1 Signature release

```bash
keytool -genkey -v -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties
# Renseigner storeFile, mots de passe, alias
```

`android/app/build.gradle.kts` utilise `key.properties` si présent ; sinon signature debug (tests locaux uniquement).

### 5.2 Play Console

- [ ] Créer l’application : package `com.acpec.fueltoken_app`.
- [ ] Téléverser **AAB** : `./scripts/run.sh build appbundle --release`.
- [ ] Fiche store : captures, description, **politique de confidentialité** (URL HTTPS obligatoire).
- [ ] Questionnaire sécurité des données (données compte, transactions carburant).
- [ ] Déclarer permissions : `CAMERA` (QR), `USE_BIOMETRIC` — justifier dans la fiche.

### 5.3 Réseau

- Release : `network_security_config` → cleartext **désactivé**.
- Debug : cleartext autorisé (`android/app/src/debug/res/xml/`).

---

## 6. iOS (App Store)

### 6.1 Xcode / identité

- [ ] Bundle ID aligné avec App Store Connect (projet `ios/Runner.xcodeproj`).
- [ ] Team, certificats Distribution, profil App Store.
- [ ] `CFBundleDisplayName` : **FuelToken**.

### 6.2 ATS (App Transport Security)

`Info.plist` : pas de chargement HTTP arbitraire ; HTTPS obligatoire en production (cohérent avec le gate Dart).

### 6.3 Privacy Manifest

Fichier : `ios/Runner/PrivacyInfo.xcprivacy` (UserDefaults / préférences).

**Action Xcode (une fois)** : ouvrir `ios/Runner.xcworkspace` → ajouter `PrivacyInfo.xcprivacy` à **Copy Bundle Resources** du target Runner si absent après `flutter build ios`.

### 6.4 App Store Connect

- [ ] Métadonnées, captures iPhone.
- [ ] **Politique de confidentialité** (URL).
- [ ] Export compliance (chiffrement — en général « utilise uniquement HTTPS standard »).
- [ ] Justifications usage : Face ID, Caméra, Photothèque (clés déjà dans `Info.plist`, en français).

---

## 7. Contenu légal & store (hors code)

À préparer côté produit / juridique :

| Élément | Android | iOS |
|---------|---------|-----|
| Politique de confidentialité | URL dans Play Console | URL dans App Store Connect |
| Conditions d’utilisation | Recommandé | Recommandé |
| Compte démo pour revue | Optionnel (identifiants test) | Souvent demandé pour apps login |
| Classification contenu | Questionnaire Play | Âge / contenu App Store |

---

## 8. CI/CD (recommandé)

Pipeline type :

1. `flutter test` + `dart analyze`
2. Injecter secrets : `ODOO_JSONRPC_BASE_URL`, keystore Android (base64), certificats iOS (match / ASC API).
3. `flutter build appbundle --release` avec `--dart-define=…`
4. Upload Play Internal Testing / TestFlight

Ne jamais passer `ALLOW_OFFLINE_DEMO=true` sur les branches store.

---

## 9. Dépannage

| Symptôme | Cause probable | Action |
|----------|----------------|--------|
| Écran « Configuration API requise » | Release sans `ODOO_JSONRPC_BASE_URL` | Rebuild avec `.env` ou dart-define |
| Écran « HTTPS requis » | URL `http://` en release | Passer en `https://` |
| `run.sh` refuse le build release | HTTP dans `.env` | Corriger l’URL |
| Android : échec réseau release | Serveur HTTP seulement | TLS sur Odoo ou build debug pour tests |
| iOS rejet ATS | Appels HTTP internet | HTTPS uniquement |
| Play : signature incorrecte | Pas de `key.properties` | Créer keystore upload |

---

## 10. Prochaines améliorations (optionnel)

- [ ] `flutter_native_splash` + écran splash brandé.
- [ ] Obfuscation Dart (`--obfuscate --split-debug-info`) pour release.
- [ ] Crash reporting (Firebase Crashlytics / Sentry) sans données sensibles en clair.
- [ ] Deep links / App Links pour notifications futures.
- [ ] Tests d’intégration `integration_test/` sur parcours login + wallet.

*Dernière mise à jour : alignée sur la politique réseau release (HTTPS), signature Android template, et gates `AppEnvironment`.*

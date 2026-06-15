# FuelToken — checklist production (push / store)

> Guide complet App Store / Play, architecture et conformité réseau : **[`STORE_DEPLOYMENT.md`](STORE_DEPLOYMENT.md)**.

## Avant le build release

1. **Analyser & tests**
   - `flutter pub get`
   - `dart analyze` (0 erreur)
   - `flutter test`

2. **Configuration compile-time (obligatoire en release)**  
   Sans **`ODOO_JSONRPC_BASE_URL`**, l’app affiche l’écran *Configuration API requise* (sauf `ALLOW_OFFLINE_DEMO=true`, réservé aux builds internes).

   **Recommandé (même `.env` que le dev)** — après `scripts/env/flutter.mobile.example.env` → `scripts/env/flutter.mobile.env` :

   ```bash
   ./scripts/run.sh build appbundle --release
   # ou : ./scripts/run.sh build apk --release
   ```

   **CI ou sans fichier `.env`** — variables explicites (URL **HTTPS** en production) :

   ```bash
   --dart-define=ODOO_JSONRPC_BASE_URL=https://votre-odoo.example
   --dart-define=ODOO_USE_ACPEC_AUTH=true
   --dart-define=ODOO_FUEL_ENABLED=true
   ```

   **OTP legacy** — `API_BASE_URL` / `OTP_API_BASE_URL` sont conservés seulement pour compatibilité historique ; le flux OTP actif passe par les routes Odoo JSON-RPC :

   ```bash
   --dart-define=ODOO_RPC_REQUEST_OTP_PATH=/api/acpec/mobile_auth/v1/request-otp
   --dart-define=ODOO_RPC_VERIFY_OTP_PATH=/api/acpec/mobile_auth/v1/verify-otp
   ```

   Voir `./scripts/run.sh` pour les `dart-define` optionnels (chemins RPC personnalisés, etc.).

3. **Icônes**  
   Source : `assets/images/logo_fueltoken_launcher.png` → `dart run flutter_launcher_icons` après toute modification.

4. **Secrets**  
   Ne pas committer clés API, secrets Odoo. CI : variables d’environnement ou secrets du dépôt.

5. **Versions store**  
   - `pubspec.yaml` : `version: x.y.z+build`
   - iOS : `ios/Runner.xcodeproj` / App Store Connect
   - Android : `versionCode` / `versionName` alignés avec Flutter

## Builds

**Android (AAB / APK)** — avec `scripts/env/flutter.mobile.env` :

```bash
./scripts/run.sh build appbundle --release
# ou
./scripts/run.sh build apk --release
```

**iOS**

```bash
./scripts/run.sh build ipa --release
```

(Puis signature / archive dans Xcode ou CI.)

## Documentation détaillée

- [`docs/ODOO_JSONRPC_INTEGRATION.md`](ODOO_JSONRPC_INTEGRATION.md)
- [`docs/ACPEC_LIVE_WORKFLOW.md`](ACPEC_LIVE_WORKFLOW.md)

*Dépôt Flutter uniquement — métier et auth via Odoo ACPEC.*

# Scripts — FuelToken

## Lancer l’application (recommandé)

| Fichier | Plateforme |
| --- | --- |
| **`run.sh`** | macOS / Linux / Git Bash |
| **`run.cmd`** | **Windows (CMD)** — recommandé |
| **`run.ps1`** | Windows (PowerShell) |
| **`setup_env.cmd`** | Windows — crée `scripts\env\flutter.mobile.env` si absent |

### Première fois

1. `flutter pub get`
2. Les fichiers **`scripts/env/flutter.mobile.env`** et **`flutter.mobile.example.env`** sont dans le dépôt (URL Odoo équipe déjà renseignée).
3. Vérifier `scripts\env\flutter.mobile.env` (explorateur ou `dir scripts\env`).
4. Depuis la racine :
   - **Windows (CMD)** : `scripts\run.cmd`
   - Windows (PowerShell) : `.\scripts\run.ps1`
   - macOS/Linux : `./scripts/run.sh`

Si `scripts\env` est vide : `git pull` puis `scripts\setup_env.cmd`.

Surcharge personnelle (optionnel) : `scripts/env/flutter.mobile.local.env` (non versionné). Voir [`env/README.md`](env/README.md).

Les arguments supplémentaires sont transmis à Flutter, par exemple :

```bash
./scripts/run.sh -d chrome
```

### Build release (APK / AAB / iOS)

Après avoir rempli **`scripts/env/flutter.mobile.env`** (au minimum `ODOO_JSONRPC_BASE_URL`), le script injecte les mêmes `--dart-define` qu’en `flutter run` — **sans** lancer Gradle si l’URL est vide (le script s’arrête avant `flutter build`).

```bash
./scripts/run.sh build apk --release
./scripts/run.sh build appbundle --release
./scripts/run.sh build ipa --release
```

Windows (PowerShell) : `.\scripts\run.ps1 build apk --release`

### Variables utiles

Voir `scripts/env/flutter.mobile.example.env` : `ODOO_JSONRPC_BASE_URL`, `ODOO_USE_ACPEC_AUTH`, `ODOO_FUEL_ENABLED`, `API_BASE_URL` (optionnel, OTP REST externe), etc.

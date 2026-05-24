# FuelToken — application mobile

**Intégration Odoo ACPEC (JSON-RPC)** : [`docs/ODOO_JSONRPC_INTEGRATION.md`](docs/ODOO_JSONRPC_INTEGRATION.md).  
**Scripts de lancement** : [`scripts/README.md`](scripts/README.md).  
**Feuille de route production** : [`docs/PRODUCTION_STEPS.md`](docs/PRODUCTION_STEPS.md).  
**Flux données live** : [`docs/ACPEC_LIVE_WORKFLOW.md`](docs/ACPEC_LIVE_WORKFLOW.md).

Application Flutter pour la gestion de bons carburant traçables, suivant la
doctrine ACPeC (lot d'achat → faces agrégées → QR → consommation station).

## Build production (stores)

Fichier **`scripts/env/flutter.mobile.env`** (versionné pour l’équipe) : au minimum **`ODOO_JSONRPC_BASE_URL`**, plus **`ODOO_USE_ACPEC_AUTH`** / **`ODOO_FUEL_ENABLED`** si besoin.

```bash
./scripts/run.sh build appbundle --release
# ou APK :
./scripts/run.sh build apk --release
```

Sans fichier `.env` (CI), repassez les `--dart-define=…` explicitement (voir [`docs/PRODUCTION_STEPS.md`](docs/PRODUCTION_STEPS.md)).

`API_BASE_URL` est **optionnel** : uniquement si vous branchez un service REST externe pour OTP / inscription.

## Lancement

```bash
flutter pub get
./scripts/run.sh
```

Config : [`scripts/env/flutter.mobile.env`](scripts/env/flutter.mobile.env) (dans `scripts/env/`, pas à la racine).

| OS | Commande |
| --- | --- |
| **Windows** | `scripts\run.cmd` ou `.\scripts\run.ps1` |
| macOS / Linux | `./scripts/run.sh` |

Après clone : `git pull` puis `dir scripts\env` (Windows) — si vide : `scripts\setup_env.cmd`. Voir [`scripts/env/README.md`](scripts/env/README.md).

Ou sans script : `flutter run` avec les `--dart-define` nécessaires.

## Auth et configuration

- **Production** : connexion et métier via **Odoo ACPEC** (`ODOO_JSONRPC_BASE_URL`, `ODOO_USE_ACPEC_AUTH`, `ODOO_FUEL_ENABLED`). Lancer l’app : **`./scripts/run.sh`** (macOS/Linux) ou **`.\scripts\run.ps1`** (Windows).
- **REST optionnel** : `API_BASE_URL` si vous maintenez un point d’accès OTP/inscription compatible avec les appels de l’app (`OtpRemoteService`).
- **Mode hors ligne (debug / démo)** : sans Odoo, dépôt en mémoire ; `ALLOW_OFFLINE_DEMO=true` en release pour builds internes (voir `AppEnvironment`).

## Architecture

```
lib/
  core/            theme, router, formatters, palette
  data/
    models/        AppUser, CarnetType, PurchaseLot, FaceLine, QrToken, …
    repositories/  AuthRepository, FuelRepository (démo mémoire si hors ligne)
  features/
    auth/          login, register (Bloc)
    home/          dashboard utilisateur
    purchases/     lots d'achat (liste, détail, soumission)
    qr/            émission, liste, détail, split
    station/       accueil station, scan caméra
    admin/         lots à valider, utilisateurs, types, stations, rapports
    transactions/  journal métier
    wallet/        cubit wallet calculé
  shared/widgets/  StatusBadge, EmptyState, SectionLabel, AppCard, …
```

State management via `flutter_bloc`. Routing via `go_router` avec
redirections par rôle (`/home`, `/admin`, `/station`).

## Réseau ACPEC (performances)

Les appels JSON-RPC passent par `AcpecFueltokenJsonRpcApi` : **requêtes identiques** fusionnées pendant l’envoi, **cache mémoire ~30 s** pour les lectures sûres — voir [`docs/ODOO_JSONRPC_INTEGRATION.md`](docs/ODOO_JSONRPC_INTEGRATION.md).

## Doctrine respectée

- Logique **lot number** : agrégation par lot + type + valeur de face.
- **Wallet calculé** : `wallet = Σ(quantité disponible × valeur de face)`.
- **Émission QR** : FIFO (expiration la plus proche), atomique, idempotente
  côté repo.
- **Split QR** : conservation stricte (somme enfants = parent), faces entières
  uniquement, parent passe en état `split`.
- **Consommation station** : QR entier uniquement, refus si bloqué/expiré, le
  QR mixte (valide + expiré) est automatiquement marqué `blocked`.
- **Profils** : nouveau compte = `user`, admin peut promouvoir.

## Couleurs (aperçu)

| Rôle    | Couleur   |
| ------- | --------- |
| Primary | `#0D6FCB` |
| Surface | `#FFFFFF` |
| Fond    | `#F5F9FF` |
| Texte   | `#0B1220` |

## Tests

```bash
flutter test
```

Un test **smoke** minimal est fourni (`test/smoke_test.dart`) pour valider la chaîne d’outils. Ajoutez des tests métier sous `test/` selon vos besoins.

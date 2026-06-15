# FuelToken — Intégration Odoo (JSON-RPC) et données dynamiques

## Vue d’ensemble de l’architecture actuelle

| Couche | Rôle aujourd’hui | Données |
| --- | --- | --- |
| **Application Flutter** (`lib/`) | UI, navigation, BLoC | `FuelRepository.instance` : **mémoire locale** + graine démo ; `AuthRepository.instance` : **mock** ; OTP / auth mobile : routes Odoo JSON-RPC dans le code courant |
| **Odoo (bundles `acpec_mobile_auth`, `acpec_fueltoken_api`)** | Contrôleurs métier **JSON-RPC** côté ERP | Source de vérité opérationnelle côté ACPEC |

La console de test navigateur fournie par votre déploiement Odoo envoie des requêtes **POST** avec enveloppe **JSON-RPC 2.0** vers des routes (`type='jsonrpc'`). Elle sert de **référence** pour les noms de méthodes et les payloads `params`.

**Important :** le mobile ne doit pas dépendre de données statiques pour le métier une fois branché : les listes (types de ticket, lots, faces, QR, stations) doivent provenir des appels réseau via un port unique (voir ci‑dessous).

---

## Stratégie d’architecture

Ce dépôt cible **Mobile → Odoo** (JSON-RPC). Le flux OTP/inscription actuellement utilisé par l'app passe par les routes Odoo documentées dans `lib/core/config/odoo_auth_rpc_config.dart`.

- **Avantages :** un saut réseau pour le métier, même enveloppe que la console de test Odoo.
- **Points d’attention :** session Odoo sur l’app, TLS, pare-feu, évolution des routes côté module.

---

## Format d’appel (aligné console de test)

En général, chaque requête suit :

```http
POST {BASE}{CHEMIN_CONTRÔLEUR}
Content-Type: application/json
```

Corps (enveloppe) :

```json
{
  "jsonrpc": "2.0",
  "method": "<nom_methode_cote_serveur>",
  "params": { ... },
  "id": 1
}
```

Réponse JSON-RPC standard :

- Succès : `{ "jsonrpc": "2.0", "id": 1, "result": ... }`
- Erreur : `{ "jsonrpc": "2.0", "id": 1, "error": { "code": ..., "message": "...", "data": ... } }`

Les **noms exacts** de `method` et la forme de `params` doivent être repris **depuis la console** ou la spécification du module Odoo (non figés dans ce dépôt tant que les routes ne sont pas exportées en OpenAPI / tableau contractuel).

---

## Performance côté client (dédup + cache)

- **Requêtes en double** : si deux appels utilisent la même route et les mêmes `params` pendant qu’une requête est déjà en vol, ils partagent le **même** `Future` (un seul aller-retour réseau).
- **Cache mémoire** : les lectures idempotentes (portefeuille, profil station, listes paginées, types de carnets, faces, détail QR, etc.) peuvent être réutilisées pendant environ **30 secondes**. Les mutations (login, consommation QR, validations admin, créations, rejets, etc.) **ne sont pas** mises en cache.
- Fichier : `lib/core/network/acpec_fueltoken_rpc_coordinator.dart` (instance partagée utilisée par défaut par `AcpecFueltokenJsonRpcApi`).

---

**Mode sans données statiques :** voir [`docs/ACPEC_LIVE_WORKFLOW.md`](ACPEC_LIVE_WORKFLOW.md) (login ACPEC, portefeuille live, écran admin des demandes de compte).

## Code Flutter ajouté (structure)

| Fichier | Rôle |
| --- | --- |
| `lib/core/config/odoo_api_config.dart` | `ODOO_JSONRPC_BASE_URL`, chemin de contrôleur |
| `lib/core/config/odoo_auth_rpc_config.dart` | Noms RPC login / session / logout (`ODOO_RPC_*`) |
| `lib/core/config/odoo_fueltoken_rpc_config.dart` | Noms RPC wallet / lots / QR / stations (`ODOO_RPC_FUEL_*`) |
| `lib/data/services/odoo_fueltoken_facade.dart` | Appels typés vers `AcpecFueltokenJsonRpcApi` + erreur si méthode non définie |
| `lib/core/auth/odoo_session_store.dart` | Persistance `session_id` + en-tête `Cookie` |
| `lib/data/services/odoo_jsonrpc_client.dart` | Client JSON-RPC 2.0 (Dio), capture session optionnelle |
| `lib/data/services/odoo_auth_service.dart` | Login / `session_me` / logout Odoo |
| `lib/data/api/acpec_fueltoken_jsonrpc_api.dart` | Appels `callRoute` vers le client JSON-RPC |
| `lib/core/network/acpec_fueltoken_rpc_coordinator.dart` | Déduplication des requêtes identiques en cours + cache mémoire TTL (~30 s) pour lectures sûres |
| `lib/data/repositories/auth_repository.dart` | Login Odoo si configuré, sinon mode local ; restauration de session |

Les **écrans métier** continuent d’utiliser `FuelRepository` jusqu’à migration : l’étape suivante consiste à introduire un **port** `FuelDataPort` (ou repository async) qui délègue soit au mock local, soit à `AcpecFueltokenJsonRpcApi` + mappers `Map → modèles` Dart existants (`PurchaseLot`, `FaceLine`, etc.).

### Auth : Odoo (session) + OTP mobile JSON-RPC

- **OTP / inscription** : routes Odoo JSON-RPC configurées par `ODOO_RPC_REQUEST_OTP_PATH` et `ODOO_RPC_VERIFY_OTP_PATH`.
- **Récupération de mot de passe** : même couple de routes OTP, avec `purpose = forgot_password`.
- Enveloppe JSON-RPC : `method` = `"call"`, contenu métier dans `params`, **une route HTTP par opération** (ex. `/api/acpec/mobile_auth/v1/login`). Catalogue : `docs/odoo_acpec_api_catalog.json`.
- **Login ACPEC** : activer `--dart-define=ODOO_USE_ACPEC_AUTH=true`. Corps : `identifier` + `secret_code` (pas `password`). Routes = module ACPEC sur votre instance Odoo.
- **Cold start** : si `ODOO_RPC_SESSION_PATH` (ou legacy `ODOO_RPC_SESSION_ME_METHOD` commençant par `/`) est actif et qu’un `session_id` est stocké, appel session pour valider la session Odoo.
- **Logout** : efface JWT (issu d’OTP) et session Odoo ; route logout ACPEC optionnelle si `ODOO_USE_ACPEC_AUTH=true`.

| Variable | Rôle |
| --- | --- |
| `ODOO_USE_ACPEC_AUTH` | `true` : login / session / logout / signup Odoo via routes `/api/acpec/...` (défaut isolé : `false` ; le script `./scripts/run.sh` peut définir `true` via `flutter.mobile.env`) |
| `ODOO_RPC_LOGIN_PATH` | Route login (défaut `/api/acpec/mobile_auth/v1/login`) |
| `ODOO_RPC_SESSION_PATH` | Session (défaut `.../session-check`) |
| `ODOO_RPC_LOGOUT_PATH` | Logout |
| `ODOO_RPC_SIGNUP_PATH` | Inscription ACPEC après OTP (défaut `.../signup`) |
| `ODOO_SIGNUP_COMPANY_ID` | `company_id` entier pour signup ACPEC (défaut `1`) |
| `ODOO_RPC_LOGIN_METHOD` / `ODOO_RPC_SESSION_ME_METHOD` / … | **Legacy** : si la valeur commence par `/`, utilisée comme route (remplace les clés `*_PATH`) |
| `ODOO_RPC_COMPLETE_REGISTRATION_METHOD` | Legacy : si la valeur commence par `/`, utilisée comme route signup |
| `ODOO_FUEL_ENABLED` | `true` : pas de graine locale métier quand Odoo est la source |
| `ODOO_ACPEC_VERSION_PATH` | Version check |
| `ODOO_ACPEC_SIGNUP_COMPANIES_PATH` | Liste sociétés inscription |
| `ODOO_RPC_FUEL_WALLET_PATH` | Portefeuille |
| `ODOO_RPC_FUEL_PURCHASES_CREATE_PATH` | Création lot d’achat |
| `ODOO_RPC_FUEL_PURCHASES_LIST_PATH` | Liste lots |
| `ODOO_RPC_FUEL_FACES_PATH` | Faces |
| `ODOO_RPC_FUEL_QR_ISSUE_PATH` | Émission QR |
| `ODOO_RPC_FUEL_QR_LIST_PATH` | Liste QR |
| `ODOO_RPC_FUEL_QR_DETAIL_PATH` | Détail QR |
| `ODOO_RPC_FUEL_QR_SPLIT_PATH` | Split QR |
| `ODOO_RPC_FUEL_QR_RETIRER_PATH` | Retirer un QR |
| `ODOO_RPC_FUEL_QR_SEPARER_PATH` | Séparer un QR |
| `ODOO_RPC_FUEL_CARNETS_TRANSFER_PATH` | Transfert de carnets |
| `ODOO_RPC_FUEL_STATION_QR_USE_PATH` | Consommation station |
| `ODOO_ACPEC_ADMIN_ACCOUNT_REQUESTS_PATH` | Liste demandes compte (admin) |

Les valeurs par défaut des routes `ODOO_RPC_FUEL_*` et `ODOO_ACPEC_*` correspondent au catalogue extrait de la console ACPEC.

**Build release** : `ODOO_JSONRPC_BASE_URL` requis, sauf `ALLOW_OFFLINE_DEMO=true`. `API_BASE_URL` / `OTP_API_BASE_URL` ne sont conservés qu'à titre legacy et ne sont pas nécessaires pour le flux OTP actuel.

## Variables de compilation (`--dart-define`)

```bash
flutter run \
  --dart-define=ODOO_JSONRPC_BASE_URL=https://VOTRE-ODOO.example \
  --dart-define=ODOO_USE_ACPEC_AUTH=true \
  --dart-define=ODOO_FUEL_ENABLED=true
```

`ODOO_JSONRPC_CONTROLLER_PATH` ne sert plus aux routes catalogue `/api/acpec/...` (conservé seulement pour compatibilité éventuelle).

---

## Ordre de test conseillé (équivalent mobile)

Reprenant la **console de test** de votre instance ACPEC FuelToken :

1. Version / sociétés (signup companies)
2. Inscription client + validation admin
3. Login / session
4. Portefeuille courant
5. Création de lot (`carnet_type_id` réel)
6. Validation du lot (backend)
7. Faces, émission QR, détail, split
8. Utilisateur station + consommation QR

Pour chaque étape, documenter dans le backlog : `method`, `params` d’exemple, structure `result`, codes d’erreur métier.

---

## Documentation liée

- Flux données live : [`docs/ACPEC_LIVE_WORKFLOW.md`](ACPEC_LIVE_WORKFLOW.md)
- Checklist production : [`docs/PRODUCTION_STEPS.md`](PRODUCTION_STEPS.md)

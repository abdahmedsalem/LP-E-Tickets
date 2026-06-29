# Audit Flutter — Endpoint Contract Map

Date : 2026-06-29
Patch : patch-flutter-endpoint-contract-audit-map
Base : mobile-runtime-v1-20260628-api-contract-alignment
Statut : audit-only, sans changement runtime

## Objectif

Cartographier les appels Flutter vers le backend Odoo et vérifier leur alignement avec le contrat API mobile public.

Ce patch est volontairement documentaire :
- aucun runtime Flutter modifié ;
- aucun backend modifié ;
- aucun refactor UI ;
- aucune correction endpoint encore appliquée.

## Sources inspectées

- `Fueltoken_Frontend/AGENTS.md`
- `Fueltoken_Frontend/PASSATION_FLUTTER_API_CONTRACT.md`
- `Fueltoken_Frontend/AUDIT_REFERENCE_FLUTTER_API.md`
- extraction `flutter_endpoint_contract_hits.txt`
- `lib/core/config/odoo_auth_rpc_config.dart`
- `lib/core/config/odoo_fueltoken_rpc_config.dart`
- `lib/data/services/odoo_auth_service.dart`
- `lib/data/services/odoo_fueltoken_facade.dart`
- écrans Flutter appelant directement `OdooFueltokenFacade`

## Verdict synthétique provisoire

Le patch précédent a bien verrouillé la couche transversale des erreurs publiques, mais il ne prouve pas encore l'alignement complet endpoint par endpoint.

La cartographie initiale montre :

| Bloc | Verdict provisoire | Commentaire |
|---|---|---|
| Transport JSON-RPC | OK déjà traité | Le patch précédent a centralisé la lecture métier `result.ok` / `error.code`. |
| Auth / OTP | Plutôt OK, à confirmer par tests réels | Flutter lit `challenge_id` s'il existe et vérifie avec ou sans `challenge_id`. |
| `device_uid` | Plutôt OK côté stabilité | Généré une fois et conservé localement. À revoir seulement si stockage sécurisé strict requis. |
| Tokens | À corriger / durcir | `AuthTokenStore` utilise `SharedPreferences`, avec commentaire de migration production vers stockage sécurisé. |
| Actions sensibles client | Partiellement OK | `action_code` est présent, `idempotency_key` est présent, mais souvent générée au moment de l'appel réseau. |
| Actions admin / BO | À arbitrer | Plusieurs endpoints `/admin/...` sont exposés dans Flutter. À classer entre mobile-admin autorisé et BO-only interdit. |
| Station QR | Partiellement OK | `station/qr/check` est lecture, `station/qr/use` a `action_code` et `idempotency_key`, mais idempotence à stabiliser par intention. |
| Mappers réponse | À vérifier endpoint par endpoint | Plusieurs mappers tolèrent beaucoup d'alias. Utile mais peut masquer un écart de contrat. |

## Routes auth ACPEC

| Domaine | Config Flutter | Endpoint / route | Params envoyés observés | Champs lus observés | Verdict | Notes |
|---|---|---|---|---|---|---|
| Auth | `loginRoute` | `/api/acpec/mobile_auth/v1/login` | à confirmer | user/tokens selon service | À confirmer | Flux historique encore présent, mais doctrine cible OTP. |
| Auth | `sessionRoute` | `/api/acpec/mobile_auth/v1/session-check` | aucun ou session courante | user/session | À confirmer | À garder si contrat backend public. |
| Auth | `refreshRoute` | `/api/acpec/mobile_auth/v1/refresh` | `device_uid` + refresh token | tokens | À confirmer | Vérifier stockage refresh et expiration. |
| Auth | `meRoute` | `/api/acpec/mobile_auth/v1/me` | Bearer | user | À confirmer | Doit porter `device_trust_state`. |
| Auth | `signupRoute` | `/api/acpec/mobile_auth/v1/signup` | signup payload | user/tokens ou demande | À confirmer | Vérifier téléphone/PIN nettoyés localement. |
| OTP | `requestOtpRoute` | `/api/acpec/mobile_auth/v1/request-otp` | phone/purpose/user_type selon flow | `challenge_id` optionnel, `delivery`, `expires_at` | OK provisoire | Flutter normalise `otp_challenge_id` depuis `challenge_id` si présent. |
| OTP | `verifyOtpRoute` | `/api/acpec/mobile_auth/v1/verify-otp` | `challenge_id` seulement si présent, OTP, `device_uid` | tokens/user/trust | OK provisoire | Conforme à la règle request-otp avec/sans challenge. |
| Auth | `logoutRoute` | `/api/acpec/mobile_auth/v1/logout` | session courante | ok | À confirmer | Pas critique contrat mutation valeur. |
| Auth | `versionCheck` | `/api/acpec/mobile_auth/v1/version-check` | optionnel | version/readiness | À confirmer | Endpoint diagnostic/readiness. |
| Auth | `signupCompanies` | `/api/acpec/mobile_auth/v1/signup-companies` | optionnel | companies | À confirmer | Lecture. |

## Routes FuelToken mobile client

| Domaine | Facade Flutter | Endpoint / route | Params envoyés observés | Champs lus observés | Verdict | Notes |
|---|---|---|---|---|---|---|
| Wallet | `walletCurrent` | `/api/acpec/fueltoken/v1/mobile/wallet/current` | `near_expiration_days`, `near_expiration_limit` | wallet, faces, expirations | À confirmer | Lecture. |
| Transactions | `transactions` | `/api/acpec/fueltoken/v1/mobile/transactions` | pagination/filtres | transactions | À confirmer | Lecture. |
| Transactions | `transactionsDetail` | `/api/acpec/fueltoken/v1/mobile/transactions/detail` | `transaction_id` | transaction detail | À confirmer | Lecture. |
| Achats | `purchasesCreate` | `/api/acpec/fueltoken/v1/mobile/purchases/create` | `lines`, `proof_filename`, `proof_data`, `payment_reference`, `action_code`, `idempotency_key` | `purchase_id`, `public_code`, `state` | À corriger partiellement | `action_code` OK. `idempotency_key` générée juste avant appel ; à stabiliser par intention utilisateur/retry. |
| Achats | `purchasesList` | `/api/acpec/fueltoken/v1/mobile/purchases` | pagination/filtres | purchases | À confirmer | Lecture. |
| Achats | `purchasesDetail` | `/api/acpec/fueltoken/v1/mobile/purchases/detail` | `purchase_id` | purchase detail | À confirmer | Lecture. |
| Faces | `faces` | `/api/acpec/fueltoken/v1/mobile/faces` | optionnel | face lines | À confirmer | Lecture. |
| Carnets | `carnetTypes` | `/api/acpec/fueltoken/v1/mobile/carnet-types` | optionnel | carnet types | À confirmer | Lecture. |
| QR | `qrIssue` | `/api/acpec/fueltoken/v1/mobile/qr/issue` | `lines`, `action_code`, `idempotency_key` | QR créé | À corriger partiellement | `idempotency_key` générée dans `_performEmit`, donc pas garantie stable sur retry. |
| QR | `qrList` | `/api/acpec/fueltoken/v1/mobile/qr/list` | filtres/list params | QR list | À confirmer | Lecture. |
| QR | `qrDetail` | `/api/acpec/fueltoken/v1/mobile/qr/detail` | `public_code` | QR detail | À confirmer | Lecture. |
| QR | `qrRetirer` | `/api/acpec/fueltoken/v1/mobile/qr/retirer` | `public_code`, `lines`, `action_code`, `idempotency_key` | `new_qr`, `source` | À corriger partiellement | `action_code` OK. Idempotence à stabiliser par intention. |
| QR | `qrSeparer` | `/api/acpec/fueltoken/v1/mobile/qr/separer` | `public_code`, `action_code`, `idempotency_key` | `new_qr`, `source` | À corriger partiellement | `action_code` OK. Idempotence à stabiliser par intention. |
| Transfert | `carnetsTransferRecipient` | `/api/acpec/fueltoken/v1/mobile/carnets/transfer/recipient` | `recipient_phone` | recipient info | À confirmer | Lecture/validation destinataire. |
| Transfert | `carnetsTransfer` | `/api/acpec/fueltoken/v1/mobile/carnets/transfer` | `recipient_phone`, `lines`, `action_code`, `idempotency_key` | transfer result | À corriger partiellement | `action_code` OK. Idempotence à stabiliser par intention. |

## Routes station

| Domaine | Facade Flutter | Endpoint / route | Params envoyés observés | Champs lus observés | Verdict | Notes |
|---|---|---|---|---|---|---|
| Station | `stationProfile` | `/api/acpec/fueltoken/v1/station/profile` | `{}` | station/operator profile | À confirmer | Lecture. |
| Station | `stationTransactions` | `/api/acpec/fueltoken/v1/station/transactions` | pagination/filtres | station transactions | À confirmer | Lecture. |
| Station QR | `stationQrCheck` | `/api/acpec/fueltoken/v1/station/qr/check` | `public_code` | `canConsume`, QR detail, totals | À confirmer | Lecture avant consommation. |
| Station QR | `stationQrUse` | `/api/acpec/fueltoken/v1/station/qr/use` | `public_code`, `action_code`, `idempotency_key` | station consume result | À corriger partiellement | `action_code` OK. `idempotency_key` générée au moment de l'appel ; à stabiliser par intention/retry. |

## Routes admin exposées dans Flutter

| Domaine | Facade Flutter | Endpoint / route | Params envoyés observés | Verdict | Notes |
|---|---|---|---|---|---|
| Admin achats | `adminPurchasesPending` | `/api/acpec/fueltoken/v1/admin/purchases/pending` | `state` | À arbitrer | Lecture admin. À confirmer mobile-admin autorisé. |
| Admin achats | `adminPurchasesDetail` | `/api/acpec/fueltoken/v1/admin/purchases/detail` | `purchase_id` | À arbitrer | Lecture admin. |
| Admin achats | `adminPurchasesApprove` | `/api/acpec/fueltoken/v1/admin/purchases/approve` | `purchase_id` | À corriger / arbitrer | Mutation sensible sans `action_code`/`idempotency_key` côté Flutter observé. |
| Admin achats | `adminPurchasesReject` | `/api/acpec/fueltoken/v1/admin/purchases/reject` | `purchase_id`, `rejection_reason` | À corriger / arbitrer | Mutation sensible sans `action_code`/`idempotency_key` côté Flutter observé. |
| Admin stations | `adminStationsList` | `/api/acpec/fueltoken/v1/admin/stations/list` | `{}` | À arbitrer | Lecture admin. |
| Admin stations | `adminStationsCreate` | `/api/acpec/fueltoken/v1/admin/stations/create` | station payload | À arbitrer fort | Configuration BO dans Flutter : vérifier si autorisée V1. |
| Admin stations | `adminStationsUpdate` | `/api/acpec/fueltoken/v1/admin/stations/update` | `station_id` + champs | À arbitrer fort | Configuration BO dans Flutter : vérifier si autorisée V1. |
| Admin stations | `adminStationsDisable` | `/api/acpec/fueltoken/v1/admin/stations/disable` | `station_id` | À arbitrer fort | Configuration BO dans Flutter : vérifier si autorisée V1. |
| Admin reports | `adminReportsSummary` | `/api/acpec/fueltoken/v1/admin/reports/summary` | `{}` | À arbitrer | Lecture dashboard admin. |
| Admin types | `adminCarnetTypesList` | `/api/acpec/fueltoken/v1/admin/carnet-types/list` | optionnel | À arbitrer | Lecture admin. |
| Admin types | `adminCarnetTypesCreate` | `/api/acpec/fueltoken/v1/admin/carnet-types/create` | `face_count`, `face_value`, `validity_days`, `company_id`, `active` | À arbitrer fort | Configuration BO dans Flutter : vérifier si autorisée V1. |
| Admin types | `adminCarnetTypesUpdate` | `/api/acpec/fueltoken/v1/admin/carnet-types/update` | `carnet_type_id` + champs | À arbitrer fort | Configuration BO dans Flutter : vérifier si autorisée V1. |
| Admin types | `adminCarnetTypesDelete` | `/api/acpec/fueltoken/v1/admin/carnet-types/delete` | `carnet_type_id` | À arbitrer fort | Configuration BO dans Flutter : vérifier si autorisée V1. |
| Admin comptes | `adminAccountRequests` | `/api/acpec/mobile_auth/v1/admin/account-requests` | list/approve/reject dynamic routes | À arbitrer | À vérifier : mobile-admin ou BO-only ? |

## Points critiques

### 1. `request-otp`

Constat :
- Flutter lit `challenge_id` s'il est présent.
- Flutter vérifie l'OTP en envoyant `challenge_id` seulement si la valeur existe.
- Le flux semble compatible avec la réponse sans `challenge_id`.

Verdict provisoire : OK, mais à tester manuellement sur compte connu et compte masqué.

### 2. `device_uid`

Constat :
- `DeviceInstallStore` génère une valeur `ft-<platform>-<uuid>` et la conserve localement.
- Les placeholders interdits `flutter-android-local`, `flutter-ios-local`, `flutter-web-local`, `web-local` ne sont pas observés dans la génération actuelle.
- `verify-otp` et `refresh` envoient `device_uid`.

Verdict provisoire : OK côté stabilité.
Point restant : stockage sécurisé strict à arbitrer, car l'identifiant n'est pas traité comme secret mais la doctrine demande un stockage fiable.

### 3. Tokens

Constat :
- `AuthTokenStore` utilise `SharedPreferences`.
- Le code indique explicitement qu'une migration production vers `flutter_secure_storage` ou trousseau plateforme est à faire.

Verdict : À corriger dans un patch sécurité mobile distinct.

### 4. `device_trust_state`

Constat :
- `AppUser` lit `device_trust_state` et `mobile_device_trust_state`.
- Le patch précédent a ajouté le routing `blocked`.
- Il faut encore tester manuellement `pending_trust`, `trusted`, `blocked` avec backend réel.

Verdict provisoire : Partiellement OK, tests réels nécessaires.

### 5. Actions sensibles

Constat :
- Plusieurs mutations client/station envoient bien `action_code`.
- Plusieurs mutations client/station envoient bien `idempotency_key`.
- Mais l'idempotency key est souvent générée directement dans le callback d'appel réseau :
  - QR issue ;
  - QR retirer ;
  - QR séparer ;
  - transfert carnets ;
  - station QR use ;
  - achat mobile.

Risque :
- en cas de retry réseau réel, Flutter peut régénérer une nouvelle clé ;
- en cas de double tap ou nouvelle exécution du callback, Flutter peut créer une nouvelle intention sans le vouloir.

Verdict : À corriger dans le prochain patch runtime ciblé.

### 6. Endpoints admin / BO

Constat :
- Flutter contient de nombreux endpoints `/admin/...`.
- Certains sont lecture dashboard/liste.
- Certains sont configuration BO : stations create/update/disable, carnet-types create/update/delete.
- Le contrat agent rappelle que les endpoints manager explicitement back-office-only ne doivent pas être exposés dans l'app mobile.

Verdict : À arbitrer avant correction.
Avocat du diable : si l'app Flutter doit être uniquement mobile client/station/manager positif, les endpoints de configuration BO doivent être retirés ou protégés par build flag/role très explicite.

## Classement provisoire

### OK provisoire

- Transport JSON-RPC transversal.
- Erreurs publiques par `error.code`.
- `request-otp` avec/sans `challenge_id`, sous réserve tests réels.
- `device_uid` stable localement.
- Station QR check en lecture.
- Endpoints lecture wallet/faces/purchases/transactions, sous réserve comparaison backend détaillée.

### À corriger en priorité

1. Stabiliser `idempotency_key` par intention utilisateur.
2. Vérifier que tout retry réseau réutilise la même clé.
3. Ne jamais générer l'idempotency key dans la fonction qui peut être rejouée automatiquement.
4. Vérifier les mutations admin : `action_code`/`idempotency_key` ou exclusion mobile.
5. Migrer les tokens vers stockage sécurisé si exigé pour V1 production.

### À arbitrer

1. Les écrans admin Flutter sont-ils réellement dans le périmètre mobile V1 ?
2. Les routes `/admin/stations/*` et `/admin/carnet-types/*` sont-elles mobile-admin autorisées ou BO-only ?
3. Le manager mobile doit-il approuver uniquement des achats, ou aussi configurer stations/types ?
4. Les endpoints admin doivent-ils rester compilés dans l'app mobile de production ?

## Prochaine étape recommandée

Patch runtime suivant :

```text
patch-flutter-sensitive-action-idempotency
```

Objectif :
- créer une abstraction `SensitiveActionIntent` ou équivalent ;
- générer `idempotency_key` une seule fois par intention utilisateur ;
- réutiliser la clé sur retry réseau ;
- ne pas régénérer à chaque tap/callback ;
- conserver `action_code` sous la seule clé backend autorisée ;
- ajouter tests unitaires sur la stabilité de l'intention.

Hors périmètre :
- pas de backend ;
- pas de refactor UI massif ;
- pas de correction des endpoints admin avant arbitrage.

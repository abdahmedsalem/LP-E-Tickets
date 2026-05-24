# ACPEC live mode (no local static fuel/auth demo)

When the app is built with **`ODOO_JSONRPC_BASE_URL`** plus either **`ODOO_USE_ACPEC_AUTH=true`** or **`ODOO_FUEL_ENABLED=true`**, it enters **live ACPEC mode**:

- No in-memory **FuelRepository** seed and no **AuthRepository** demo users (`AppEnvironment.useAcpecLiveData`).
- **Login / session / logout** use the JSON-RPC routes configured for your Odoo instance (`method: "call"`, payload in `params`).
- **Home route** (`/home` vs `/admin` vs `/station`) follows **`AppUser.role`** from the API only. Mapping is centralized in `lib/data/models/acpec_user_role_resolver.dart` (`is_superuser`, `is_admin`, `groups` / `group_ids`, string fields such as `user_type`, `permissions` / `scopes`, flags such as `can_approve_account_requests`). **No email allowlist** in the app.
- **Wallet** on the client home screen loads via `OdooFueltokenFacade` (`wallet/current` route on the server).
- **Admin → Demandes de compte ACPEC** calls the admin JSON-RPC routes (`account-requests`, approve, reject). You must be logged in as an **ACPEC administrator** so the HTTP client sends a valid Odoo session cookie.

## Recommended run command

```bash
cp scripts/env/flutter.mobile.example.env scripts/env/flutter.mobile.env
# Éditer ODOO_JSONRPC_BASE_URL dans scripts/env/flutter.mobile.env
./scripts/run.sh
```

(Default values in `flutter.mobile.example.env`: `ODOO_USE_ACPEC_AUTH=true`, `ODOO_FUEL_ENABLED=true`.)

## Administrator testing

- Admin capabilities match your server’s catalogue: list pending signup requests, approve or reject by id, then affected users can use mobile wallet/QR flows as implemented on the server.
- **Do not commit real passwords.** Use credentials issued for your ACPEC/Odoo environment only.

## Registration → logout → login

1. Complete signup in ACPEC/Odoo (and/or external REST OTP + Odoo signup, depending on your `API_BASE_URL` setup).
2. **Logout** clears the stored Odoo session and JWT.
3. **Login** again with the same identifier and password to obtain a new session.

## Other mobile APIs

Wallet, purchases, faces, QR (issue / list / detail / split) and station scan use the FuelToken JSON-RPC routes on your Odoo host when **`AppEnvironment.useAcpecLiveData`** is active. Catalogue : `docs/odoo_acpec_api_catalog.json`, façade : `lib/data/services/odoo_fueltoken_facade.dart`.

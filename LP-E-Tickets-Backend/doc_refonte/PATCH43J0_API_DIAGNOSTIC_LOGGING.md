# Patch43J0 — API diagnostic logging production-safe

## Objet

J0 ajoute une fondation de logs diagnostic API utilisable temporairement en production.

Le but est de faciliter le débogage mobile/backend sans transformer les logs Odoo en coffre de secrets.

## Doctrine

Les payloads bruts frontend/backend ne sont jamais loggés.

Les logs diagnostic sont :

```text
- redacted ;
- bornés en taille ;
- grepables ;
- corrélables par endpoint/opération/référence ;
- activables temporairement en production ;
- désactivés automatiquement après expiration.
```

## Paramètres

```text
acpec_mobile_auth.api_diagnostic_logging_enabled = 1
acpec_mobile_auth.api_diagnostic_logging_until = YYYY-MM-DD HH:MM:SS
```

Sans date future dans `api_diagnostic_logging_until`, le diagnostic détaillé IN/OUT reste désactivé.

## Marqueurs logs

```text
[[ACPEC_FUELTOKEN_API_IN]]
[[ACPEC_FUELTOKEN_API_OUT]]
[[ACPEC_FUELTOKEN_API_REFUSED]]
[[ACPEC_FUELTOKEN_API_ERR]]
```

## Interdits

Ne jamais logger en clair :

```text
action_code / PIN
OTP
tokens
password
qr_numeric_code
public_code QR
idempotency_key
proof_data / base64
```

Les valeurs sensibles sont remplacées par présence, longueur et hash court `sha256_12`.

## Endpoint pilote J0

J0 applique les hooks diagnostic IN/OUT au flux :

```text
/api/acpec/fueltoken/v1/mobile/tickets/transfer
```

Les refus/erreurs passent aussi par les marqueurs distinctifs côté helper commun.

## Nettoyage futur

Tous les ajouts sont grepables avec :

```bash
git grep -n "ACPEC_FUELTOKEN_API_"
git grep -n "api_diagnostic_logging"
```

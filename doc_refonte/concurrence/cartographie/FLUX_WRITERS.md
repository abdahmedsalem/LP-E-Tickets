# Flux writers FuelToken

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : inventaire initial
```

## 1. API économiques

```text
/mobile/purchases/create
/admin/purchases/approve
/admin/purchases/reject
/mobile/qr/issue
/mobile/qr/retirer
/mobile/qr/separer
/mobile/tickets/transfer
/mobile/carnets/transfer
/station/qr/use
```

Flux portail associés :

- achat société ;
- distribution ;
- transfert de tickets.

## 2. API potentiellement mutatives malgré une apparence de lecture

```text
/station/qr/check
/mobile/qr/reveal-code
```

Plus généralement, toute route appelant un helper de rafraîchissement
d'expiration ou de création contrôlée doit être classée comme writer.

## 3. Authentification et sécurité

```text
/mobile_auth/v1/request-otp
/mobile_auth/v1/verify-otp
/mobile_auth/v1/signup
/mobile_auth/v1/password-login
/mobile_auth/v1/confirm-pin
/mobile_auth/v1/refresh
/mobile_auth/v1/logout
/admin/account-requests/...
/admin/devices/approve
```

## 4. Back-office et wizards

Familles de writers significatifs :

- achat : submit/approve/reject ;
- transfert carnet : confirm/cancel ;
- transfert ticket : confirm/cancel ;
- QR : transitions et actions internes ;
- distribution société ;
- régularisation station ;
- trust/block/reset device ;
- revoke/trust/block session ;
- approbation/refus de demande de compte ;
- stations et types de carnet.

## 5. Crons et maintenance

```text
cron expiration face_line / QR
cron purge error markers
autovacuum OTP verify buckets
```

## 6. Effets externes

Appel externe confirmé :

```text
request OTP → fournisseur SMS Chinguisoft
```

Avant toute allowlist de retry, rechercher également :

- email ;
- push ;
- webhook ;
- message bus ;
- paiement ou autre service tiers.

## 7. Règle d'exhaustivité

Cet inventaire est le point de départ de la baseline indiquée.

Avant une décision sur une ressource, compléter la recherche avec :

```text
write()
create()
unlink()
SQL FOR UPDATE
lock_timeout / NOWAIT / SKIP LOCKED
savepoint
message_post
requests/http client
crons
actions XML et boutons
```

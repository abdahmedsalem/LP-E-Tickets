# Décision de groupe — OTP et SMS

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : OUVERT — appel externe identifié
```

## 1. Fait

Le flux OTP appelle un fournisseur SMS externe avec un timeout.

`service.model.retrying()` ne résout pas un timeout du fournisseur.

Inversement, si le SMS est accepté puis que la transaction Odoo rollbacke,
le rejeu de toute la route peut déclencher un second SMS.

## 2. Invariants

- un OTP est consommé une seule fois ;
- les compteurs et buckets sont cohérents ;
- un code envoyé doit correspondre à un challenge valable ;
- aucun code n'apparaît dans les logs ;
- un timeout fournisseur ne doit pas être interprété arbitrairement comme échec ;
- un retry ne doit pas envoyer plusieurs SMS non maîtrisés.

## 3. Options à comparer

### Appel synchrone sans retry de la route

Simple, mais l'issue fournisseur peut rester inconnue.

### Idempotence fournisseur

Même clé ou identifiant fournisseur, si le contrat Chinguisoft le permet.

### Outbox / job durable

Transaction locale :

```text
challenge + delivery pending
```

Worker :

```text
envoi + statut + retries + réconciliation
```

### Réconciliation

Consulter le statut par identifiant fournisseur, si disponible.

## 4. Tests obligatoires

- fournisseur accepte puis `40001` avant commit ;
- timeout après acceptation simulée ;
- deux demandes OTP simultanées ;
- réponse mobile perdue ;
- plusieurs retries du job ;
- expiration du challenge pendant la livraison.

## 5. Décision actuelle

```text
GUIDELINE : route avec effet externe non idempotent
non éligible par défaut au retry de toute la requête.
```

Le choix synchrone/outbox reste ouvert jusqu'à vérification du contrat fournisseur
et des exigences de latence OTP.

# État de l'art — concurrence, retries et idempotence dans les systèmes mobiles

```text
version       : 1.0
date_revue    : 2026-07-13
nature        : référence externe non normative
baseline      : sans objet
```

## 1. Finalité

Ce document décrit des pratiques utilisées dans les systèmes mobiles,
transactionnels et financiers.

Il ne décide pas automatiquement de l'architecture FuelToken.

Pour chaque pratique, il faut vérifier :

- le problème réellement traité ;
- les préconditions ;
- les effets secondaires ;
- la latence acceptable ;
- le contrat client ;
- l'applicabilité au runtime Odoo ;
- les résultats de tests FuelToken.

## 2. Séparation des problèmes

Les références convergent vers une séparation entre :

```text
exactitude des données
idempotence de l'intention
retry transactionnel serveur
retry ou redo client
traitement asynchrone des effets externes
```

Ces mécanismes sont complémentaires.

Un retry ne corrige pas un invariant incorrect.
Un verrou ne résout pas une réponse réseau perdue.
Une clé d'idempotence ne définit pas l'ordre des verrous.
Une outbox ne remplace pas la validation métier.

## 3. Écritures mobiles online-only et offline

Android distingue plusieurs stratégies d'écriture :

- online-only ;
- queued writes ;
- lazy writes ;
- synchronisation offline-first.

Une opération financière ou irréversible peut être classée online-only :
l'utilisateur doit connaître son résultat et l'application ne doit pas
l'exécuter silencieusement plus tard sans contrat explicite.

Application potentielle FuelToken :

```text
consommation, transfert, émission QR
→ candidates online-only

logs, analytics, certaines purges
→ candidats à une file ou un traitement différé
```

Référence :

- [Android — Build an offline-first app](https://developer.android.com/topic/architecture/data-layer/offline-first)

## 4. Intention persistée et réponse perdue

Une réponse perdue crée une issue inconnue :

```text
le serveur peut avoir committé
le client n'a pas reçu le résultat
```

La pratique courante des APIs financières consiste à :

- créer une clé stable pour l'intention ;
- rejouer avec la même clé et les mêmes paramètres ;
- retourner le résultat déjà committé ;
- refuser la même clé avec une intention différente.

La clé représente l'intention, pas une tentative réseau.

Références :

- [Stripe — Idempotent requests](https://docs.stripe.com/api/idempotent_requests)
- [Adyen — API idempotency](https://docs.adyen.com/development-resources/api-idempotency)
- [IETF draft — Idempotency-Key HTTP Header Field](https://datatracker.ietf.org/doc/html/draft-ietf-httpapi-idempotency-key-header-07)

Attention : le document IETF est un Internet-Draft, pas une norme finale.

## 5. Fingerprint canonique

Une clé seule ne suffit pas. Le serveur doit pouvoir détecter :

```text
même clé + même intention
même clé + intention différente
```

Le fingerprint doit être calculé sur un sous-ensemble métier stable.

À exclure généralement :

- la clé elle-même ;
- les secrets ;
- les tokens ;
- les timestamps non métier ;
- la locale ;
- l'ordre d'insertion JSON.

À définir par action :

- champs inclus ;
- normalisation ;
- ordre des collections ;
- traitement de `null` et des valeurs absentes ;
- durée de rétention.

## 6. Retry transactionnel PostgreSQL

PostgreSQL recommande de rejouer la transaction complète après une erreur
de sérialisation éligible.

Le retry doit inclure la logique qui a décidé :

- les lectures ;
- les valeurs ;
- les préconditions ;
- les écritures.

Un retry peut lui-même échouer ; le nombre de tentatives et le backoff
sont des paramètres de disponibilité, pas des vérités universelles.

Référence :

- [PostgreSQL — Serialization Failure Handling](https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html)

## 7. Ordre des verrous et deadlocks

PostgreSQL recommande d'acquérir les verrous sur plusieurs objets dans un
ordre cohérent entre les transactions.

Le deadlock est résolu par l'annulation d'une transaction, mais la stratégie
primaire reste la cohérence de l'ordre d'acquisition.

Référence :

- [PostgreSQL — Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)

## 8. Runtime Odoo 19

Les curseurs applicatifs Odoo 19 utilisent `REPEATABLE READ`.

Odoo possède un mécanisme de retry à la frontière transactionnelle qui :

- rollbacke ;
- réinitialise l'environnement ;
- applique un backoff ;
- retente certaines erreurs de concurrence.

Il ne résout pas automatiquement :

- les timeouts d'un fournisseur HTTP externe ;
- les réponses externes perdues ;
- les doubles effets produits avant le rollback Odoo.

Références :

- [Odoo 19 — `sql_db.py`](https://raw.githubusercontent.com/odoo/odoo/19.0/odoo/sql_db.py)
- [Odoo 19 — `service/model.py`](https://raw.githubusercontent.com/odoo/odoo/19.0/odoo/service/model.py)
- [Odoo 19 — `http.py`](https://raw.githubusercontent.com/odoo/odoo/19.0/odoo/http.py)

## 9. Backoff, jitter et budget de retry

Les recommandations courantes incluent :

- classification des erreurs ;
- maximum de tentatives ;
- backoff exponentiel ;
- jitter ;
- budget global de retry ;
- arrêt immédiat sur erreur terminale ;
- métriques de succès et d'épuisement.

Le retry ne doit pas amplifier une panne ou une contention.

Référence :

- [AWS — Retry behavior](https://docs.aws.amazon.com/sdkref/latest/guide/feature-retry-behavior.html)

## 10. Effets externes

Un appel externe peut réussir alors que la transaction locale rollbacke ensuite.

Exemples :

```text
SMS accepté, puis rollback Odoo
paiement externe accepté, puis 40001
webhook envoyé, puis transaction annulée
```

Stratégies courantes :

- idempotence fournie par le prestataire ;
- outbox transactionnelle ;
- job durable ;
- réconciliation par identifiant fournisseur ;
- séparation entre décision locale et livraison externe.

Une automated action seule n'est pas nécessairement une file durable fiable.
Le traitement doit avoir un état, un nombre de tentatives, une prochaine date,
un résultat et une politique d'issue inconnue.

## 11. Crons revisités

Pour un traitement revisitable :

- batch court ;
- progression durable ;
- savepoint par unité si justifié ;
- reprise au passage suivant ;
- métrique de backlog ;
- détection de famine.

`SKIP LOCKED` peut augmenter le débit, mais rend une passe non exhaustive et
peut affamer une ligne chaude.

Référence :

- [Odoo 19 — Actions and scheduled actions](https://www.odoo.com/documentation/19.0/developer/reference/backend/actions.html)

## 12. Points sans solution universelle

Il n'existe pas de valeur universelle pour :

- le nombre de retries ;
- le `lock_timeout` ;
- l'utilisation de `NOWAIT` ;
- l'utilisation de `SKIP LOCKED` ;
- l'ordre global des ressources ;
- le TTL d'une clé ;
- le passage synchrone ou asynchrone d'un effet externe.

La solution dépend de :

```text
invariant
ressources partagées
writers concurrents
latence
effets externes
contrat client
capacité de réconciliation
mesures runtime
```

## 13. Usage dans FuelToken

Ce document sert à générer des hypothèses et des tests.

Il ne doit jamais être cité seul pour justifier un patch.
La décision FuelToken doit être enregistrée dans `decisions/` après
cartographie et expérimentation.

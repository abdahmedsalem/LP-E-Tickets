# 07 - Idempotence et anti-rejeu métier

## Portée

Ce module définit l'idempotence, le `request_hash`, la protection double-spend, et l'ordre transactionnel.

Lire avec `00_decisions_invariants.md` et `06_odoo_integration.md`.

## 7.1 Deux gardes obligatoires

Les opérations sensibles ont besoin de deux gardes distinctes.

```text
Garde 1 - clé d'idempotence
-> protège contre le même appel rejoué par retry client.

Garde 2 - verrouillage d'objet
-> protège contre deux appels différents visant le même objet.
```

Une seule des deux ne suffit jamais.

## 7.2 Clé d'idempotence

La clé est générée par le client avant l'appel :

```text
idempotency_key
```

Portée d'unicité :

```text
operation_type
operator_user_id
idempotency_key
```

Ajouter `company_id` si périmètre multi-société :

```text
unique(company_id, operation_type, operator_user_id, idempotency_key)
```

Sinon :

```text
unique(operation_type, operator_user_id, idempotency_key)
```

Règle critique :

```text
mobile_session_id et device_uid ne sont jamais dans la clé unique.
```

Raison : un retry après reconnexion ou nouvelle session doit rester idempotent.

## 7.3 Request hash

La table d'idempotence stocke un `request_hash` calculé sur le contenu métier stable.

Exemples de composants :

```text
operation_type
ticket_id / qr_id
amount
target_wallet_id
company_id
station_id
```

Règle :

```text
Même idempotency_key + même request_hash
-> retourner résultat mémorisé.

Même idempotency_key + request_hash différent
-> refuser idempotency_conflict.
```

## 7.4 Réponse mémorisée

Pour permettre un replay propre, mémoriser :

```text
status
business_record_model
business_record_id
response_code
safe_response_json
created_at
completed_at
```

Ne jamais mémoriser :

```text
tokens ;
OTP ;
PIN ;
secrets ;
données sensibles inutiles.
```

## 7.5 TTL / rétention

Recommandation V1 :

```text
QR / ticket / transfert / transaction financière
-> clés conservées au moins 90 jours.
```

Même si la clé expire :

```text
un ticket consommé reste consommé.
```

## 7.6 Verrouillage d'objet

La clé d'idempotence ne protège pas contre deux clés différentes ciblant le même ticket.

Pour QR/ticket :

```sql
UPDATE acpec_fuel_ticket
SET state = 'consumed', ...
WHERE id = :ticket_id
AND state = 'active';
```

Puis vérifier :

```text
nombre de lignes affectées = 1
```

Si 0 ligne : refus métier clair.

Alternative : table consommation avec `unique(ticket_id)`.

## 7.7 Ordre transactionnel

```text
1. Vérifier idempotency_key.
   Si déjà vue avec même request_hash -> retourner résultat mémorisé.

2. Si déjà vue avec request_hash différent -> idempotency_conflict.

3. Verrouiller / transitionner conditionnellement l'objet métier.
   Si objet non consommable -> refus métier clair.

4. Exécuter l'opération.

5. Mémoriser résultat idempotent.

6. Commit unique : idempotence + objet + transaction métier.
```

## 7.8 Tests minimum

```text
- même clé + même payload -> même résultat ;
- même clé + payload différent -> idempotency_conflict ;
- double consommation concurrente même clé -> une seule opération ;
- double consommation concurrente clés différentes -> une seule consommation ;
- mobile_session_id différent ne casse pas l'idempotence ;
- objet déjà consommé refuse clairement ;
- response_json ne contient pas secrets.
```


## Additif patch23A — idempotency_key obligatoire sur mutations économiques

Les endpoints suivants exigent désormais idempotency_key en plus du device trusted et du PIN serveur action_code :

- /api/acpec/fueltoken/v1/mobile/purchases/create
- /api/acpec/fueltoken/v1/mobile/qr/issue
- /api/acpec/fueltoken/v1/mobile/qr/retirer
- /api/acpec/fueltoken/v1/mobile/qr/separer
- /api/acpec/fueltoken/v1/mobile/carnets/transfer
- /api/acpec/fueltoken/v1/station/qr/use

Les endpoints de lecture, détail, profil, historique et check non mutatif restent sans idempotency_key obligatoire.

Ce patch ne remplace pas le futur request_hash. Il rend seulement la clé obligatoire là où le moteur métier accepte déjà une clé idempotente.

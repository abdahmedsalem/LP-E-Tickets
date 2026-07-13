# Guide ACPEC d'évaluation de la concurrence — FuelToken

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
nature        : guide de méthode
```

## 1. Principe

Il n'existe pas une solution unique applicable à toutes les actions FuelToken.

La méthode est uniforme ; la politique est spécialisée selon :

- l'invariant ;
- les ressources ;
- les writers ;
- l'erreur ;
- le canal ;
- les effets externes ;
- la reprise client.

## 2. Catégories d'affirmations

Chaque fiche doit utiliser explicitement :

```text
FAIT
INVARIANT
GUIDELINE
OPTION
EXPERIENCE
DECISION
REJET
OUVERT
```

Une `OPTION` n'autorise aucun patch.

## 3. Séquence obligatoire

### Étape A — définir l'action et l'invariant

Documenter :

- entrée métier ;
- résultat terminal ;
- états intermédiaires ;
- conservation attendue ;
- doublons interdits ;
- ressource canonique de l'invariant.

### Étape B — recenser les ressources

Inclure :

- modèles Odoo ;
- lignes SQL ;
- contraintes ;
- compteurs ;
- séquences ;
- ressources externes ;
- état mobile local.

### Étape C — recenser tous les writers

Ne pas s'arrêter au canal initial.

Chercher :

```text
API
portail
BO
wizard
cron
autovacuum
import
script
méthode interne
```

### Étape D — relever l'ordre actuel

Pour chaque writer :

- première lecture ;
- première acquisition de verrou ;
- autres ressources verrouillées ;
- ids triés ou non ;
- relecture après verrou ;
- écritures ;
- effets externes ;
- commit implicite ou explicite.

### Étape E — construire les scénarios croisés

Minimum :

```text
même opération × même objet
même opération × objets différents partageant une ressource
opération A × opération B
API × BO
API × cron
BO × cron
```

### Étape F — observer avant de corriger

Mesurer :

- SQLSTATE ;
- attente ;
- deadlock ;
- rollback ;
- invariant final ;
- nombre d'effets ;
- réponse publique ;
- comportement du client ;
- audit et markers.

### Étape G — comparer les options

Options possibles, non automatiques :

```text
contrainte SQL
mise à jour atomique conditionnelle
FOR UPDATE
ordre global des verrous
NOWAIT
lock_timeout
SKIP LOCKED
savepoint
retry Odoo
redo client même clé
outbox/job
réconciliation
```

### Étape H — choisir la solution minimale

La solution retenue doit :

- protéger l'invariant ;
- couvrir les writers croisés ;
- ne pas masquer un deadlock structurel ;
- ne pas doubler un effet externe ;
- respecter le budget de latence ;
- être observable ;
- avoir un kill-switch si elle modifie la politique de retry.

## 4. Faits techniques déjà confirmés

### Odoo

```text
FAIT : les curseurs Odoo 19 utilisent REPEATABLE READ.
```

```text
FAIT : le moteur `service.model.retrying()` agit à la frontière transactionnelle.
```

### Savepoint

```text
FAIT : un savepoint ne fournit pas un nouveau snapshot.
```

```text
REJET : retry d'un 40001 avec seulement savepoint + try/except.
```

### Codes PostgreSQL

```text
40001 : erreur de sérialisation, retry complet éventuellement pertinent.
55P03 : verrou indisponible ; politique dépendante de la ressource.
40P01 : deadlock ; incident d'ordre à investiguer.
```

### Mobile

```text
FAIT : un timeout peut masquer un commit réussi.
```

```text
GUIDELINE : conserver la même intention et la même clé tant que
l'issue n'est pas terminale.
```

### Effets externes

```text
FAIT : un appel externe peut réussir avant un rollback Odoo.
```

```text
GUIDELINE : une route contenant un effet externe non idempotent
n'est pas éligible par défaut au retry de toute la requête.
```

## 5. Uniformité et factorisation

### À uniformiser

- format des fiches ;
- helpers de verrouillage par classe de ressource ;
- tri des ids ;
- canonicalisation des fingerprints ;
- classification des erreurs ;
- métriques ;
- kill-switches ;
- stockage des intentions mobiles ;
- présentation des décisions.

### À ne pas sur-factoriser

Ne pas créer un helper universel qui décide automatiquement :

- quel verrou ;
- quel timeout ;
- quel retry ;
- quel code public ;
- quel backoff ;
- quel traitement externe.

La politique reste explicite par action ou groupe d'invariants.

## 6. Tests requis avant allowlist retry

1. rollback complet prouvé ;
2. aucun effet externe dupliqué ;
3. même clé/même payload prouvé ;
4. même clé/payload différent refusé ;
5. réponse perdue testée ;
6. order des verrous croisés testé ;
7. métriques disponibles ;
8. budget de latence validé ;
9. erreur terminale publique définie ;
10. comportement Flutter validé.

## 7. Fiche standard de décision

```yaml
id:
statut:
baseline:
invariant:
ressources:
writers:
ordre_actuel:
risques:
preuves:
options_comparees:
decision:
solutions_rejetees:
effets_externes:
contrat_idempotence:
politique_40001:
politique_55p03:
politique_40p01:
contrat_mobile:
metriques:
kill_switch:
tests:
commit_tag:
points_ouverts:
```

## 8. Règle de progression

Une ressource peut être étudiée avant les autres, mais la décision ne doit pas
ignorer les opérations multi-ressources.

Ordre de travail recommandé :

```text
1. cartographie globale peu profonde
2. face_line + QR + QR lines
3. wallets + transferts
4. achats
5. user + device + session
6. OTP + SMS
7. crons et maintenance, en parallèle des ressources qu'ils touchent
```

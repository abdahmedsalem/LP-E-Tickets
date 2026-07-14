# Roadmap — refonte RPC ACPEC FuelToken V1

```text
Référence      : A1-R
Version        : 1.0
Statut         : actif — roadmap progressive
Date           : 14 juillet 2026
Baseline       : b827fc3
Doctrine       : DOCTRINE_ARCHITECTURE_RPC_ACPEC_FUELTOKEN_V1.md
```

## 1. Principe de conduite

La refonte progresse par patches courts. Le runtime stable n’est remplacé qu’après preuve.
Aucune étape ne suppose que la suivante est déjà réalisée.

```text
documenter
→ identifier le contrat
→ construire le wrapper
→ migrer une lecture pilote
→ adapter Flutter en tolérance
→ migrer progressivement
→ traiter PIN
→ traiter OTP
→ rendre strict
→ retirer le legacy
```

## 2. État de départ

### Déjà réalisé

```text
Patch43M24-B
→ exceptions de concurrence admissibles laissées au retry natif Odoo

Patch43M24-C
→ frontière terminale ACPEC JSON-RPC
→ SERVER_ERROR public générique
→ aucune fuite d’exception inconnue

Flutter Phase 1
→ Dio signale les non-2xx
→ OdooJsonRpcClient conserve l’analyse JSON-RPC
→ 175 tests verts après alignement des gardes
```

### Non encore réalisé

```text
_acpec_rpc généralisé
AcpecRpcError commun
@acpec_rpc_endpoint
registre de migration des routes
normalisation data/error route par route
reconnaissance Flutter du marqueur
guards PIN intégrés à la nouvelle frontière
OTP sous politique spécialisée
suppression du fallback legacy
```

## 3. Phases

### Phase D0 — doctrine et roadmap

Type : documentation uniquement.

Livrables :

- doctrine A1 ;
- roadmap A1-R ;
- mise à jour `00_index.md` ;
- consignes `AGENTS.md` ;
- section de traçabilité.

Critères de clôture :

- aucun fichier runtime ;
- `git diff --check` ;
- revue humaine de l’architecture ;
- commit et push dans le fork ACPEC.

### Phase D1 — marqueur backend additif

Objectif :

Ajouter :

```json
"_acpec_rpc": {
  "service": "fueltoken",
  "version": 1
}
```

sans déplacer les clés existantes.

Périmètre :

- succès existants ;
- erreurs publiques existantes ;
- `SERVER_ERROR` M24-C ;
- tests prouvant que le reste du payload est inchangé.

Interdits :

- création du wrapper complet ;
- migration générale sous `data` ;
- modification Flutter ;
- modification métier.

Critères de clôture :

- tests ciblés marqueur ;
- tests M24-C ;
- run backend élargi vert ;
- inspection dynamique d’une réponse succès et d’une erreur.

### Phase D2 — primitives RPC communes

Objectif :

Introduire les briques sans migrer massivement les routes :

```text
AcpecRpcError
serializer/envelope builder
@acpec_rpc_endpoint
tests unitaires purs
```

Le wrapper doit prouver :

- savepoint ;
- pas de commit ;
- erreur publique explicite ;
- exception inconnue relancée ;
- concurrence relancée ;
- marqueur exact ;
- logging sûr.

Critères :

- aucun contrôleur métier migré, ou seulement contrôleur artificiel de test ;
- API publique inchangée ;
- tests dédiés verts.

### Phase D3 — endpoint pilote lecture seule

Choisir une route :

- simple ;
- sans PIN ;
- sans OTP ;
- sans effet externe ;
- sans mutation ;
- payload clairement documenté.

Candidats :

```text
version/readiness public borné
carnet types
wallet current en lecture, seulement si contrat stabilisé
```

Livrables :

- contrôleur mince ;
- wrapper canonique ;
- serializer public ;
- registre route `canonical_v1` ;
- tests anciens + nouveaux.

Critères :

- payload cible `{_acpec_rpc, ok, success, data}` ;
- compatibilité Flutter vérifiée ;
- aucune régression route legacy voisine.

### Phase D4 — Flutter reconnaît le marqueur

Objectif :

Ajouter une reconnaissance centrale :

```text
marqueur présent et valide
→ contrat ACPEC V1

marqueur absent
→ fallback legacy temporaire

marqueur présent mais invalide/inconnu
→ réponse serveur non reconnue
```

Périmètre :

- `OdooJsonRpcClient` ou guard ACPEC existant ;
- aucun duplicat de framework ;
- pas de refonte UI ;
- tests marker/service/version.

Critères :

- toutes les routes existantes continuent à fonctionner ;
- route pilote reconnue ;
- aucun logout fondé uniquement sur un marqueur absent d’une route legacy.

### Phase D5 — lectures ordinaires

Migrer les endpoints de lecture par petits groupes cohérents :

```text
catalogues
wallet
carnets
QR list/detail sans reveal
transactions/history
station read-only
manager read-only
```

Pour chaque route :

- serializer allowlisté ;
- code public stable ;
- statut registre ;
- test contrat ;
- test rôle/société/device ;
- test absence de références internes sensibles.

### Phase D6 — mutations ordinaires sans PIN/OTP

Migrer les mutations qui n’ont pas d’effet externe et dont la politique de concurrence
est déjà prouvée.

Exigences :

- idempotence selon la doctrine concurrence ;
- verrous dans le modèle ;
- contrôleur mince ;
- erreur publique explicite ;
- aucune régression BO/portail/cron.

Exclure encore :

- actions PIN ;
- request/verify OTP ;
- SMS ;
- refresh/session protocol complexe si non stabilisé.

### Phase D7 — actions sensibles PIN

Migrer une action à la fois :

```text
transfert
consommation QR
émission/retrait/séparation QR
achat/approbation selon rôle
```

Livrables communs :

- guard `sensitive_action` ;
- `action_code` non loggé ;
- device trusted ;
- rôle requis ;
- idempotency key / intent ;
- comportement « non confirmé » après panne ambiguë ;
- tests replay et concurrence.

Ordre recommandé :

1. action la mieux couverte par idempotence existante ;
2. consommation QR ;
3. transfert ;
4. achats ;
5. autres actions sensibles.

### Phase D8 — session et refresh spécialisés

Avant OTP, revoir les protocoles :

- access token ;
- refresh family ;
- logout ;
- device block ;
- replay grace ;
- erreurs `AUTH_REQUIRED` et `SESSION_EXPIRED`.

But :

- distinguer erreur applicative ACPEC d’un HTTP 401 brut ;
- préserver les invariants device/session ;
- éviter logout indu par proxy.

### Phase D9 — OTP/SMS

Traiter séparément :

```text
request_otp
verify_otp
signup
forgot PIN
reset PIN
```

Sous-phases :

1. cartographie des effets externes ;
2. décision outbox/après-commit ;
3. request sans retry générique ;
4. verify avec challenge verrouillé ;
5. rate limit et antiflood ;
6. tests de duplication SMS ;
7. tests de consommation unique.

OTP reste le dernier domaine fonctionnel migré.

### Phase D10 — mode strict Flutter route par route

Le registre backend publie ou documente les routes strictes.

Flutter applique :

```text
route legacy
→ marqueur facultatif

route strict_v1
→ marqueur obligatoire
→ service/version exacts
→ enveloppe canonique obligatoire
```

Critères :

- aucun faux positif ;
- messages utilisateurs sûrs ;
- télémétrie des réponses legacy résiduelles.

### Phase D11 — fermeture du legacy

Conditions préalables :

- toutes les routes en `canonical_v1` ou spécialisées ;
- Flutter déployé avec support strict ;
- aucune route legacy utilisée ;
- métriques/diagnostics confirmés ;
- tests end-to-end complets.

Actions :

- supprimer fallback legacy Flutter ;
- supprimer builders de payload historiques ;
- imposer `{ok, success, data/error}` ;
- archiver le registre de migration ;
- publier la version canonique finale.

## 4. Découpage Git recommandé

```text
Patch43M24-D  doc-only doctrine + roadmap
Patch43M24-E  backend marker additif
Patch43M24-F  primitives AcpecRpcError + wrapper
Patch43M24-G  endpoint pilote lecture
Flutter F2    reconnaissance marker avec fallback
Patch suivants migration par familles
PIN           série dédiée
OTP           série finale dédiée
```

Les identifiants peuvent être ajustés, mais les responsabilités ne doivent pas être
regroupées artificiellement.

## 5. Matrice de décision avant chaque route

```yaml
route:
status_before:
status_after:
auth_odoo:
mobile_session_required:
trusted_device_required:
role_required:
pin_required:
otp_required:
external_effects:
resources_read:
resources_written:
lock_policy:
idempotency_policy:
native_retry_allowed:
public_success_shape:
public_error_codes:
legacy_flutter_dependency:
tests:
rollback:
```

Une route ne démarre pas sa migration sans fiche remplie.

## 6. Critères globaux de succès

La refonte est réussie lorsque :

- les modèles sont Odoo standards ;
- les contrôleurs sont courts ;
- la mécanique commune est unique ;
- aucune exception inconnue n’est publique ;
- chaque erreur métier a un code documenté ;
- Flutter ne dépend pas de textes libres ;
- PIN, OTP et session sont distincts ;
- les retries respectent la doctrine concurrence ;
- aucune référence interne sensible n’est exposée ;
- toutes les routes sont versionnées ;
- le fallback legacy est retiré avec preuve.

## 7. Kill criteria

Arrêter ou découper une phase si :

- elle exige une migration massive ;
- elle mélange backend et Flutter sans compatibilité ;
- elle introduit un second framework parallèle ;
- elle modifie le métier sans doctrine ;
- elle nécessite un commit manuel dans un modèle ;
- elle expose un message technique ;
- elle autorise un retry d’effet externe non prouvé ;
- elle ne peut pas être rollbackée route par route.

## 8. Prochaine action après le patch documentaire

La prochaine action autorisée est uniquement :

```text
Phase D1 — marqueur backend additif
```

Le marqueur doit être ajouté sans déplacer les clés existantes. Le wrapper complet,
la normalisation `data/error` et l’adaptation Flutter restent hors périmètre de D1.

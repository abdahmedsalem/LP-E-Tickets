# Doctrine d’architecture RPC ACPEC FuelToken V1

```text
Référence      : A1
Version        : 1.0
Statut         : canonique — fondation de la refonte RPC progressive
Date           : 14 juillet 2026
Projet         : FuelToken / Tickets Carburant
Organisation   : ACPEC SARL
Baseline       : b827fc3 — Patch43M24-C final ACPEC JSON-RPC error boundary
```

## 1. Objet

Cette doctrine fixe l’architecture cible des échanges entre l’application Flutter et
le backend Odoo FuelToken, la répartition des responsabilités, le contrat public ACPEC,
le traitement des erreurs et la stratégie de migration progressive.

La représentation fonctionnelle officielle est :

```text
Flutter ↔ Dio ↔ wrapper ACPEC RPC ↔ contrôleur mince ↔ Odoo
```

La chaîne technique détaillée est :

```text
Flutter UI / Bloc
↕
OdooJsonRpcClient
↕
Dio
↕
HTTP + JSON-RPC
↕
dispatcher / routeur Odoo
↕
@acpec_rpc_endpoint — wrapper backend
↕
guards spécialisés session / rôle / PIN / OTP
↕
contrôleur mince
↕
modèles Odoo / ORM / contraintes / règles métier
```

Le wrapper n’est pas un service intermédiaire autonome. Il est exécuté dans Odoo,
autour du contrôleur, après la résolution de la route JSON-RPC.

## 2. Autorité et priorité

A1 complète les doctrines sécurité, métier, mode dev/test et concurrence. Elle ne peut
jamais les relâcher.

En cas de conflit :

```text
sécurité > métier > concurrence > architecture RPC > conventions > UX > dev
```

La doctrine de concurrence garde l’autorité sur les verrous, retries, idempotence et
effets externes. A1 définit où ces mécanismes sont appliqués dans la pile RPC.

## 3. Objectifs

La refonte doit :

- revenir à du code Odoo standard dans les modèles ;
- rendre les contrôleurs courts et lisibles ;
- centraliser la mécanique RPC commune dans un wrapper/décorateur ;
- distinguer transport HTTP, enveloppe JSON-RPC et payload ACPEC ;
- publier uniquement des erreurs métier explicitement autorisées ;
- conserver M24-C comme frontière terminale pour les erreurs inattendues ;
- préserver les retries natifs Odoo admissibles ;
- isoler les actions PIN et OTP des endpoints ordinaires ;
- migrer route par route sans rupture Flutter ni migration massive ;
- produire un contrat versionné et testable.

## 4. Non-objectifs

Cette refonte n’est pas :

- une réécriture complète du backend ;
- un framework parallèle à Odoo ;
- une migration de tous les contrôleurs dans un seul patch ;
- une introduction de services métier RPC dans les modèles ;
- une exposition directe des exceptions Odoo au mobile ;
- une dépendance métier aux codes HTTP ;
- une suppression immédiate des payloads legacy ;
- une fusion du PIN, de l’OTP et de la session ;
- une autorisation de retry générique sur les effets externes ;
- une refonte Flutter massive avant disponibilité du contrat backend.

## 5. Invariants d’architecture

```text
INV-RPC-001  Les modèles métier restent indépendants de HTTP, JSON-RPC, Flutter,
             `_acpec_rpc`, `ok`, `success`, `data` et `error`.

INV-RPC-002  Les contrôleurs orchestrent et sérialisent ; ils ne portent pas la
             plomberie commune de réponse, de logging ou de frontière technique.

INV-RPC-003  Le wrapper RPC est l’unique propriétaire de l’enveloppe ACPEC canonique
             pour les routes migrées.

INV-RPC-004  Une erreur n’est publique que si elle est levée ou traduite explicitement
             comme erreur ACPEC publique.

INV-RPC-005  Aucun code public n’est déduit du texte d’une exception Odoo.

INV-RPC-006  Toute exception inconnue est relancée vers la frontière terminale M24-C,
             qui retourne `SERVER_ERROR` sans détail interne.

INV-RPC-007  Les exceptions de concurrence autorisées par la doctrine de concurrence
             traversent wrapper et frontière terminale pour laisser Odoo appliquer son
             retry natif.

INV-RPC-008  Aucun contrôleur ni modèle ne fait de `cr.commit()` pour construire une
             réponse API normale.

INV-RPC-009  Le wrapper peut employer un savepoint ; un savepoint n’est jamais un commit.

INV-RPC-010  Les contrôleurs FuelToken `auth='public'` utilisent le payload ACPEC comme
             vérité applicative d’authentification, d’autorisation et de métier.

INV-RPC-011  Un HTTP non-2xx brut est une anomalie de transport, d’infrastructure ou de
             contrat ; il ne constitue pas une erreur métier FuelToken fiable.

INV-RPC-012  Le marqueur `_acpec_rpc` est versionné et ajouté sans déplacer les clés
             legacy avant migration canonique de la route.

INV-RPC-013  Une route ne devient stricte côté Flutter qu’après déclaration backend
             explicite de son statut canonique.

INV-RPC-014  Les actions PIN sont des step-up d’action pour une session déjà authentifiée ;
             elles ne créent pas une session et ne remplacent pas l’OTP.

INV-RPC-015  Les endpoints OTP sont spécialisés ; `request_otp` n’est pas soumis à un
             retry générique pouvant dupliquer un SMS.

INV-RPC-016  Les logs, références publiques et payloads ne contiennent jamais PIN, OTP,
             token, traceback, SQL, secret ou `debug_reason` de production.

INV-RPC-017  La migration se fait par petits patches, avec compatibilité legacy et tests
             de non-régression à chaque étape.

INV-RPC-018  Les serializers publics n’exposent que des identifiants et champs destinés
             au mobile ; les séquences internes restent réservées au back-office.
```

## 6. Responsabilités par couche

### 6.1 Flutter

Flutter est propriétaire de :

- l’interface et la navigation ;
- l’état Bloc ;
- la demande de PIN ou OTP dans le bon flow ;
- la présentation d’un `error.code` public ;
- la décision UX de reconnexion lorsque le contrat ACPEC le demande ;
- le message « opération non confirmée » après une panne ambiguë ;
- la compatibilité temporaire entre routes legacy et canoniques.

Flutter ne décide pas :

- si un QR est consommable ;
- si un transfert est autorisé ;
- si un device est trusted ;
- si un achat peut être approuvé ;
- si une exception backend est publiable.

### 6.2 OdooJsonRpcClient

Le client RPC Flutter est propriétaire de :

- la construction de la requête JSON-RPC ;
- la lecture de `result` ou `error` JSON-RPC ;
- la gestion technique de session déjà définie ;
- la conversion sûre des erreurs Dio ;
- l’absence de fuite HTML, traceback ou message réseau brut.

Il ne traduit pas une règle métier en inspectant un texte libre.

### 6.3 Dio

Dio est uniquement le transport HTTP :

- connexion ;
- timeout ;
- statut ;
- headers ;
- décodage JSON ;
- `Response` ou `DioException`.

Dio consomme l’enveloppe HTTP brute mais conserve ses données utiles dans
`Response` / `DioException`. Il ne retire pas l’enveloppe JSON-RPC contenue dans le body.

### 6.4 Dispatcher Odoo

Le dispatcher :

- résout la route ;
- gère l’enveloppe JSON-RPC native ;
- ouvre et clôt la transaction Odoo ;
- applique les retries natifs admissibles.

Il reste implicite dans la représentation fonctionnelle courte.

### 6.5 Wrapper ACPEC RPC

Le wrapper, matérialisé par un décorateur cible tel que `@acpec_rpc_endpoint`, est
propriétaire de la mécanique commune :

- ajout de `_acpec_rpc` ;
- construction de l’enveloppe canonique pour les routes migrées ;
- savepoint contrôlé ;
- conversion de `AcpecRpcError` en erreur publique ;
- cohérence `ok == success` ;
- logging sûr et référence publique ;
- validation du type de résultat ;
- propagation des exceptions de concurrence ;
- relance des exceptions inconnues vers M24-C ;
- options déclaratives de guards spécialisés.

Le wrapper ne :

- devine pas le métier ;
- parse pas le texte des exceptions ;
- fait pas de commit ;
- transforme pas toute `ValidationError` en erreur publique ;
- applique pas automatiquement un PIN ou un OTP ;
- réessaie pas aveuglément les mutations.

### 6.6 Guards spécialisés

Les guards communs peuvent vérifier :

- access token / session mobile ;
- société FuelToken ;
- état utilisateur ;
- device et trust ;
- rôle mobile ;
- action sensible PIN ;
- challenge OTP.

Ils retournent un contexte d’acteur ou lèvent une erreur ACPEC publique explicite.

### 6.7 Contrôleur mince

Le contrôleur :

1. reçoit les paramètres ;
2. appelle les guards requis ;
3. résout les records publics ;
4. appelle une méthode métier Odoo ;
5. sérialise les données publiques ;
6. traduit explicitement un petit nombre d’exceptions métier connues.

Il n’entoure pas toute sa méthode d’un `except Exception`.

### 6.8 Modèles Odoo

Les modèles :

- portent les invariants ;
- utilisent l’ORM et les contraintes ;
- acquièrent les verrous métier requis ;
- exécutent les mutations ;
- retournent des records ou valeurs métier ;
- restent utilisables depuis BO, portail, cron et tests.

Ils ne connaissent pas `AcpecRpcError`, sauf helper exceptionnel situé explicitement
dans une couche API et non dans le cœur économique.

## 7. Contrat ACPEC RPC V1

### 7.1 Marqueur

```json
{
  "_acpec_rpc": {
    "service": "fueltoken",
    "version": 1
  }
}
```

Règles :

- `service` vaut exactement `fueltoken` ;
- `version` est un entier ;
- le marqueur identifie le contrat, il ne prouve pas à lui seul le succès ;
- une version inconnue est refusée en mode strict ;
- le marqueur est injecté par la frontière API, jamais par le modèle métier.

### 7.2 Succès canonique cible

```json
{
  "_acpec_rpc": {
    "service": "fueltoken",
    "version": 1
  },
  "ok": true,
  "success": true,
  "data": {}
}
```

### 7.3 Erreur publique canonique cible

```json
{
  "_acpec_rpc": {
    "service": "fueltoken",
    "version": 1
  },
  "ok": false,
  "success": false,
  "error": {
    "code": "QR_NOT_USABLE",
    "message": "Ce QR n’est plus utilisable."
  }
}
```

Champs optionnels autorisés dans `error` :

```text
reference
public_action
retry_after
details publics explicitement allowlistés
```

### 7.4 Migration additive

Pendant la première étape, une route legacy :

```json
{
  "ok": true,
  "balance": 100
}
```

devient seulement :

```json
{
  "_acpec_rpc": {
    "service": "fueltoken",
    "version": 1
  },
  "ok": true,
  "balance": 100
}
```

Aucune clé n’est déplacée sous `data` dans le patch d’ajout du marqueur.

La normalisation `{ok, success, data/error}` intervient route par route lorsque le
contrôleur est migré vers le wrapper canonique.

## 8. Les trois frontières d’erreur

### 8.1 Transport HTTP

Exemples :

- réseau absent ;
- DNS ;
- connexion refusée ;
- timeout ;
- proxy ;
- Nginx ;
- HTTP non-2xx ;
- certificat.

Cette couche est traitée par Dio et `OdooJsonRpcClient`. Elle ne porte pas les codes
métier FuelToken.

### 8.2 Enveloppe JSON-RPC Odoo

Exemple :

```json
{
  "jsonrpc": "2.0",
  "error": {}
}
```

Elle représente une erreur native du dispatcher, une route hors contrat ou une
défaillance technique avant production d’un payload ACPEC.

### 8.3 Payload ACPEC

Exemple :

```json
{
  "_acpec_rpc": {
    "service": "fueltoken",
    "version": 1
  },
  "ok": false,
  "success": false,
  "error": {
    "code": "AUTH_REQUIRED",
    "message": "Session mobile requise."
  }
}
```

Cette couche est la vérité applicative pour :

- authentification mobile ;
- autorisation ;
- trust device ;
- rôles ;
- PIN ;
- OTP ;
- rate limit ;
- règles métier.

## 9. `AcpecRpcError`

`AcpecRpcError` est une erreur de frontière API :

```python
raise AcpecRpcError(
    code="QR_NOT_USABLE",
    message="Ce QR n’est plus utilisable.",
)
```

Elle signifie que l’erreur est :

- attendue ;
- stable ;
- publiable ;
- sans détail interne ;
- couverte par un test de contrat.

Elle peut être levée par :

- un contrôleur ;
- un guard API ;
- un adaptateur API.

Elle ne doit pas devenir l’exception générique des modèles métier.

### 9.1 Traduction explicite

Autorisé :

```python
try:
    qr.action_consume_by_station(...)
except ValidationError:
    raise AcpecRpcError(
        code="QR_NOT_USABLE",
        message="Ce QR n’est plus utilisable.",
    )
```

à condition que :

- le `try` soit local et étroit ;
- le cas soit réellement déterministe ;
- le code public soit documenté ;
- le texte interne ne soit pas copié ;
- un test prouve la traduction.

Interdit :

```python
except ValidationError as exc:
    raise AcpecRpcError(code=str(exc), message=str(exc))
```

## 10. Erreurs inconnues et M24-C

Flux canonique :

```text
erreur publique explicite
→ wrapper
→ payload ACPEC ok=false

exception inconnue
→ rollback savepoint
→ relance
→ frontière terminale M24-C
→ SERVER_ERROR + référence publique
```

M24-C reste un filet de sécurité terminal. Il ne doit pas devenir le mécanisme normal
de traduction métier.

## 11. Transactions, concurrence et retries

Le wrapper respecte la doctrine de concurrence.

Il doit relancer sans conversion prématurée notamment :

```text
LockNotAvailable
SerializationFailure
DeadlockDetected
ConcurrencyError
```

lorsque la doctrine et Odoo permettent le retry natif.

Règles :

- pas de `cr.commit()` ;
- savepoint possible ;
- rollback atomique sur erreur publique ;
- idempotence requise selon l’opération ;
- aucun retry ACPEC personnalisé sans allowlist ;
- aucun retry générique d’un effet externe ;
- les opérations sensibles gardent leur politique spécifique.

## 12. Traitement spécial du PIN

Le PIN est un step-up d’action pour une session déjà authentifiée.

```text
session valide
+ user autorisé
+ device trusted
+ rôle requis
+ action_code valide
+ idempotency_key / intent cohérent
→ mutation sensible
```

Le PIN :

- ne crée pas une session ;
- ne remplace pas l’OTP ;
- ne doit pas être stocké dans une transaction métier ;
- ne doit jamais être loggé ;
- ne doit pas être inclus dans une référence d’erreur ;
- ne doit pas être rejoué automatiquement après une réponse ambiguë.

Le guard cible peut être :

```python
@acpec_rpc_endpoint(sensitive_action="station-qr-use")
```

ou :

```python
@acpec_rpc_endpoint()
@require_sensitive_action("station-qr-use")
```

Le nom final est à fixer lors du patch d’implémentation. La responsabilité, elle, est
déjà fermée : le guard est à la frontière API, pas dans le modèle `acpec.fuel.qr`.

Pour une panne après envoi d’une mutation PIN :

```text
ne pas conclure « refus métier »
→ afficher « opération non confirmée »
→ consulter l’historique ou utiliser l’idempotence avant redo
```

## 13. Traitement spécial de l’OTP

L’OTP prouve la possession du numéro ou autorise un flow d’identité. Il est distinct de
la session et du PIN.

```text
OTP
→ preuve de possession / challenge

access token + refresh token
→ session

PIN / action_code
→ confirmation d’action sensible
```

### 13.1 `request_otp`

`request_otp` a un effet externe : l’envoi SMS.

Règles :

- pas de retry générique après déclenchement de l’envoi ;
- rate limit et antiflood ;
- challenge expirant ;
- aucun OTP dans les logs ;
- aucun secret SMS dans les erreurs ;
- échec provider traité sans exposer le fournisseur ;
- idempotence ou outbox à étudier avant toute automatisation de retry.

### 13.2 `verify_otp`

`verify_otp` doit :

- verrouiller le challenge ;
- vérifier expiration et finalité ;
- incrémenter les tentatives atomiquement ;
- refuser la réutilisation ;
- consommer le challenge une seule fois ;
- créer/continuer la session uniquement après succès.

Codes publics typiques :

```text
OTP_INVALID
OTP_EXPIRED
OTP_TOO_MANY_ATTEMPTS
RATE_LIMITED
```

### 13.3 Ordre de migration

OTP/SMS est migré en dernier, après :

- lectures simples ;
- mutations ordinaires ;
- actions PIN ;
- stabilisation du wrapper ;
- tests dynamiques des retries et effets externes.

## 14. Statuts de migration des routes

Chaque route est classée dans un registre :

```text
legacy
marker_additive
canonical_v1
strict_v1
special_pin
special_otp
```

Définitions :

- `legacy` : payload historique, aucun marqueur obligatoire ;
- `marker_additive` : marqueur ajouté, structure historique conservée ;
- `canonical_v1` : wrapper et enveloppe cible utilisés ;
- `strict_v1` : Flutter exige marqueur/service/version ;
- `special_pin` : route canonique avec guard d’action sensible ;
- `special_otp` : politique OTP dédiée.

Une route ne passe au statut suivant qu’après tests backend et Flutter.

## 15. Tests obligatoires

### 15.1 Wrapper

```text
T-RPC-001 succès avec marqueur exact
T-RPC-002 erreur AcpecRpcError normalisée
T-RPC-003 exception inconnue relancée vers M24-C
T-RPC-004 aucune fuite traceback/debug_reason
T-RPC-005 savepoint rollback sans commit
T-RPC-006 exceptions concurrence propagées
T-RPC-007 résultat invalide refusé fail-closed
T-RPC-008 cohérence ok/success
```

### 15.2 Migration additive

```text
T-RPC-009 payload legacy inchangé sauf `_acpec_rpc`
T-RPC-010 liste/objet/primitive supportés selon contrat route
T-RPC-011 Flutter legacy toléré
T-RPC-012 Flutter route stricte refuse marqueur absent/inconnu
```

### 15.3 PIN

```text
T-RPC-013 PIN absent/invalide refusé par code public
T-RPC-014 PIN jamais loggé
T-RPC-015 idempotency replay cohérent
T-RPC-016 timeout produit état non confirmé, pas faux refus
T-RPC-017 device non trusted refusé avant mutation
```

### 15.4 OTP

```text
T-RPC-018 request_otp sans retry générique SMS
T-RPC-019 challenge verrouillé et consommé une fois
T-RPC-020 tentative atomique
T-RPC-021 OTP absent des logs
T-RPC-022 rate limit public stable
```

## 16. Règles de patch

Tout patch de la refonte doit :

1. annoncer le statut de route avant/après ;
2. citer les `INV-RPC-*` visés ;
3. ne mélanger qu’une responsabilité principale ;
4. fournir tests ciblés ;
5. lancer le run élargi pertinent ;
6. mettre à jour le registre de migration ;
7. mettre à jour `traceability.md` ;
8. ne pas changer Flutter et backend dans le même commit, sauf patch de contrat
   explicitement approuvé ;
9. éviter `git add .` ;
10. conserver le code stable tant que le remplacement n’est pas prouvé.

## 17. Décisions fermées

```text
DEC-RPC-001  Architecture fonctionnelle :
             Flutter ↔ Dio ↔ wrapper ↔ contrôleur ↔ Odoo.

DEC-RPC-002  Le wrapper est un décorateur backend dans Odoo.

DEC-RPC-003  `_acpec_rpc.service = "fueltoken"` et `version = 1`.

DEC-RPC-004  Le premier ajout du marqueur est strictement additif.

DEC-RPC-005  Modèles Odoo standards, sans connaissance du contrat mobile.

DEC-RPC-006  Contrôleurs minces ; plomberie dans le wrapper.

DEC-RPC-007  AcpecRpcError reste à la frontière API.

DEC-RPC-008  M24-C traite l’inattendu ; il ne traduit pas le métier.

DEC-RPC-009  PIN et OTP ont des politiques spécialisées distinctes.

DEC-RPC-010  OTP/SMS est migré en dernier.

DEC-RPC-011  Migration route par route avec fallback legacy temporaire.

DEC-RPC-012  Le code Flutter actuel reste stable jusqu’à disponibilité backend du
             marqueur ; aucune simplification HTTP urgente n’est imposée.
```

## 18. Points ouverts

```text
OPEN-RPC-001  Module propriétaire de `AcpecRpcError` et du décorateur.
OPEN-RPC-002  Signature exacte de `@acpec_rpc_endpoint`.
OPEN-RPC-003  Forme finale du guard PIN.
OPEN-RPC-004  Registre technique des routes et emplacement.
OPEN-RPC-005  Stratégie outbox/après-commit pour SMS.
OPEN-RPC-006  Liste minimale d’exceptions Odoo traduisibles explicitement.
OPEN-RPC-007  Date de suppression du fallback Flutter legacy.
OPEN-RPC-008  Simplification éventuelle de la classification HTTP Flutter.

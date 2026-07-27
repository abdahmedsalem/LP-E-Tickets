# 03 - Sessions et tokens

## Portée

Ce module définit les sessions mobiles, access token, refresh token, rotation avec fenêtre de grâce et révocations.

Lire avec `00_decisions_invariants.md`.

## 3.1 Session mobile

Champs minimum :

```text
user_id
session_id
device_uid
platform
app_version
access_token_hash
current_refresh_token_hash
previous_refresh_token_hash
previous_refresh_valid_until
previous_refresh_retry_count
access_token_expires_at
refresh_token_expires_at
state
device_trust_state
last_seen_at
last_refresh_at
revoked_at
revocation_reason
ip_address
user_agent
```

États session :

```text
active
expired
revoked
blocked
```

## 3.2 Access token

Règles :

```text
- durée courte ;
- jamais loggé en clair ;
- stocké localement en secure storage ;
- validé côté serveur ;
- inutilisable après expiration.
```

## 3.3 Refresh token

Règles :

```text
- durée longue ;
- stocké localement en secure storage ;
- stocké côté serveur uniquement hashé ;
- rotatif ;
- révocable ;
- lié à une session ;
- lié à un device de façon indicative.
```

`device_uid` est une donnée d'audit/corrélation, pas une preuve cryptographique forte.

## 3.4 Rotation avec fenêtre de grâce

Scénario à éviter :

```text
1. Client appelle /refresh.
2. Serveur valide et génère une nouvelle paire.
3. Réponse réseau perdue.
4. Client garde ancien refresh token.
5. Ancien token déjà invalidé.
6. Prochain /refresh refusé.
7. OTP forcé à tort.
```

Décision :

```text
Refresh token rotatif avec fenêtre de grâce courte, fixe, non extensible.
refresh_grace_seconds = 30 à 60.
```

## 3.5 On ne renvoie jamais un token perdu

Le serveur ne stocke que le hash du refresh token.

Il ne peut pas renvoyer le token en clair perdu.

Sur retry dans la fenêtre de grâce :

```text
générer une nouvelle paire ;
renvoyer cette nouvelle paire ;
abandonner la paire perdue.
```

## 3.6 Algorithme /refresh

Le backend verrouille la ligne de session pendant toute l'opération.

```text
h = hash(token reçu)

CAS 1 - h == current_refresh_token_hash
    générer (new_access, new_refresh)
    previous_refresh_token_hash = current_refresh_token_hash
    previous_refresh_valid_until = now + refresh_grace_seconds
    previous_refresh_retry_count = 0
    current_refresh_token_hash = hash(new_refresh)
    last_refresh_at = now
    retourner (new_access, new_refresh)

CAS 2 - h == previous_refresh_token_hash
        ET now <= previous_refresh_valid_until
        ET même session
        ET previous_refresh_retry_count acceptable
    générer (new_access, new_refresh)
    current_refresh_token_hash = hash(new_refresh)
    NE PAS prolonger previous_refresh_valid_until
    previous_refresh_retry_count += 1
    journaliser refresh_retry_in_grace
    retourner (new_access, new_refresh)

CAS 3 - h == previous_refresh_token_hash
        ET now > previous_refresh_valid_until
    révoquer session
    reason = refresh_reuse_out_of_grace
    refuser -> retour OTP

CAS 4 - token inconnu
    refuser
    journaliser
    révoquer selon politique
```

## 3.7 Compromis assumé

Pendant la fenêtre de grâce, le backend ne distingue pas parfaitement :

```text
retry réseau légitime
vs
rejeu rapide par token volé.
```

Accepté car :

```text
fenêtre courte ;
fenêtre non extensible ;
retries limités ;
hors fenêtre, réutilisation révoque session.
```

## 3.8 Révocation

User ou device bloqué :

```text
- révocation immédiate des sessions concernées ;
- effacement serveur des hash current et previous refresh ;
- state session = revoked ;
- reason explicite.
```

Retrait rôle ou passage device en `pending_trust` :

```text
- effet au plus tard au prochain check access token ;
- pour effet immédiat : révoquer les sessions du device concerné.
```

## 3.9 Tests minimum

```text
- session créée après OTP ;
- access expiré -> refresh OK ;
- refresh token rotatif ;
- ancien refresh accepté uniquement en fenêtre de grâce ;
- retry dans fenêtre ne prolonge pas previous_refresh_valid_until ;
- retry_count excessif révoque/refuse selon politique ;
- ancien refresh hors fenêtre révoque ;
- token inconnu refusé ;
- blocage user/device efface current + previous refresh ;
- erreur réseau ne logout pas.
```

<!-- PATCH32B_SESSION_LIFECYCLE_BOUNDARY_START -->

## Patch32B — Limite explicite sur le lifecycle session

Patch32B ne modifie pas le cycle de vie des sessions mobiles.

Non inclus en Patch32B :

- pas de révocation automatique des anciennes sessions actives lors d’un nouvel OTP ;
- pas de contrainte stricte “une seule session active par device” ;
- pas de réutilisation/rotation OTP-aware d’une session longue existante ;
- pas d’héritage automatique du trust entre sessions.

Ces sujets sont reportés à un patch lifecycle dédié après stabilisation du `device_install_uid` côté Flutter.

<!-- PATCH32B_SESSION_LIFECYCLE_BOUNDARY_END -->

<!-- PATCH32D_BACKEND_SESSION_LIFECYCLE_START -->

## Patch32D — Lifecycle session après OTP login avec device stable

Patch32D corrige le comportement futur des sessions créées par OTP login lorsque le mobile envoie un `device_uid` stable issu de Patch32C.

Décision retenue :

- un login OTP continue de créer une nouvelle ligne `acpec.mobile.session` pour garder une trace d’audit claire ;
- si `device_uid` est stable au format `ft-*`, les anciennes sessions actives du même couple `user_id + device_uid` sont passées en `rotated` ;
- `rotated_to_session_id` pointe vers la nouvelle session active ;
- aucune fenêtre de grâce refresh n’est accordée aux anciennes sessions rotatées par OTP login ;
- les anciens placeholders non fiables comme `flutter-android-local` restent exclus de cette rotation automatique.

Limites assumées :

- pas de nettoyage global automatique des anciennes sessions historiques ;
- pas de réutilisation de la même ligne session ;
- pas d’héritage automatique du trust device après OTP login ;
- le refresh token garde sa logique existante de rotation avec grâce contrôlée.

<!-- PATCH32D_BACKEND_SESSION_LIFECYCLE_END -->

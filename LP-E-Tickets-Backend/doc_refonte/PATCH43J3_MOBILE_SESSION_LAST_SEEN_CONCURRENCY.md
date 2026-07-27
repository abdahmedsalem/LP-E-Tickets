# Patch43J3 - Mobile session last_seen_at concurrency

## Objectif

Reduire les erreurs PostgreSQL SerializationFailure observees sur les appels mobiles paralleles utilisant le meme access token et donc la meme ligne acpec.mobile.session.

## Cause

Les endpoints mobiles proteges passent par l'authentification bearer.

Avant ce patch, authenticate_access_token() ecrivait last_seen_at a chaque requete avec une ecriture directe sur la session mobile.

Avec plusieurs appels paralleles du meme telephone, cette ecriture repetee devenait un point chaud sur la meme ligne session.

## Correction

Le patch remplace l'ecriture directe de last_seen_at par un touch throttle et best-effort.

Regles appliquees :

- ecriture uniquement si last_seen_at est absent ou trop ancien ;
- seuil actuel : ACCESS_LAST_SEEN_TOUCH_MIN_SECONDS = 60 ;
- ecriture encapsulee dans un savepoint ;
- SerializationFailure et DeadlockDetected sur le touch last_seen_at sont ignores proprement et journalises en info ;
- la session reste validee ou refusee selon les regles existantes.

## Hors perimetre volontaire

Le patch ne modifie pas :

- expiration access token ;
- expiration refresh token ;
- rotation refresh token ;
- revocation ;
- trust device ;
- controles PIN/action_code ;
- ecritures metier sensibles.

Les mutations securite de refresh, rotation et revocation restent strictes.
